import Foundation
import Network
import Security

enum ServerEvent {
    case serverStarted(UInt16)
    case serverFailed(Error)
    case request(method: String, path: String, bodyPreview: String)
    case labelPreview(zpl: String, imageData: Data)
}

struct BrowserPrintDevice: Codable {
    let name: String
    let uid: String
    let connection: String
    let deviceType: String
    let provider: String
    let manufacturer: String
    let version: Int

    static func zebra(port: UInt16) -> BrowserPrintDevice {
        BrowserPrintDevice(
            name: "emu",
            uid: "localhost:\(port)",
            connection: "network",
            deviceType: "printer",
            provider: "com.zebra.ds.webdriver.desktop.provider.DefaultDeviceProvider",
            manufacturer: "Zebra Technologies",
            version: 5
        )
    }
}

struct BrowserPrintAvailableResponse: Codable {
    let printer: [BrowserPrintDevice]

    static func single(_ device: BrowserPrintDevice) -> BrowserPrintAvailableResponse {
        BrowserPrintAvailableResponse(printer: [device])
    }
}

final class ServerController {
    private let port: UInt16
    private let onEvent: (ServerEvent) -> Void
    private let renderer = ZPLRenderer()
    private let tlsIdentityManager = TLSIdentityManager()
    private var listener: NWListener?

    init(port: UInt16, onEvent: @escaping (ServerEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    func start() {
        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 9100)
            let listener = try NWListener(using: tlsParameters(), on: nwPort)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: .global(qos: .userInitiated))
                self.readRequest(on: connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.onEvent(.serverStarted(self.port))
                case .failed(let error):
                    self.onEvent(.serverFailed(error))
                default:
                    break
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            onEvent(.serverFailed(error))
        }
    }

    private func tlsParameters() throws -> NWParameters {
        let material = try tlsIdentityManager.loadOrCreateIdentity()
        let tlsOptions = NWProtocolTLS.Options()
        guard let localIdentity = sec_identity_create_with_certificates(material.identity, material.certificates as CFArray) else {
            throw TLSIdentityError.identityImportFailed
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, localIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        return NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func readRequest(on connection: NWConnection) {
        receiveUntilComplete(on: connection, buffer: Data()) { [weak self] data in
            guard let self, let data else {
                connection.cancel()
                return
            }

            let request = HTTPRequest.parse(data: data)
            let response = self.route(request: request)
            connection.send(content: response.serializedData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func receiveUntilComplete(on connection: NWConnection, buffer: Data, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if error != nil {
                completion(nil)
                return
            }

            var next = buffer
            if let data {
                next.append(data)
            }

            if HTTPRequest.isCompletePayload(next) || isComplete {
                completion(next)
            } else {
                self.receiveUntilComplete(on: connection, buffer: next, completion: completion)
            }
        }
    }

    private func route(request: HTTPRequest?) -> HTTPResponse {
        guard let request else {
            return HTTPResponse(statusCode: 400, body: "Invalid request")
        }

        let preview = String(data: request.body.prefix(240), encoding: .utf8) ?? "<binary body>"
        onEvent(.request(method: request.method, path: request.path, bodyPreview: preview))

        if request.method == "OPTIONS" {
            return HTTPResponse(statusCode: 204, body: "", additionalHeaders: corsHeaders)
        }

        let normalizedPath = request.pathWithoutQuery
        let device = BrowserPrintDevice.zebra(port: port)
        switch (request.method, normalizedPath) {
        case ("GET", "/available"):
            return jsonResponse(BrowserPrintAvailableResponse.single(device))
        case ("GET", "/default"):
            return jsonResponse(device)
        case ("POST", "/write"):
            handleWrite(request)
            return jsonResponse(["status": "ok", "message": "Print captured by emulator"])
        case ("GET", "/read"), ("POST", "/read"):
            return HTTPResponse(statusCode: 200, body: "", additionalHeaders: corsHeaders)
        case ("GET", "/"):
            return HTTPResponse(statusCode: 200, body: "Zebra Browser Print Emulator", additionalHeaders: corsHeaders)
        default:
            return HTTPResponse(statusCode: 404, body: "Not Found", additionalHeaders: corsHeaders)
        }
    }

    private func handleWrite(_ request: HTTPRequest) {
        guard let zpl = String(data: request.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !zpl.isEmpty else {
            return
        }

        guard zpl.contains("^XA") else {
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let imageData = try? await self.renderer.render(zpl: zpl) {
                self.onEvent(.labelPreview(zpl: zpl, imageData: imageData))
            }
        }
    }

    private func jsonResponse<T: Encodable>(_ value: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(value), let body = String(data: data, encoding: .utf8) {
            var headers = corsHeaders
            headers["Content-Type"] = "application/json"
            return HTTPResponse(statusCode: 200, body: body, additionalHeaders: headers)
        }
        return HTTPResponse(statusCode: 500, body: "Failed to encode JSON", additionalHeaders: corsHeaders)
    }

    private var corsHeaders: [String: String] {
        [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        ]
    }
}
