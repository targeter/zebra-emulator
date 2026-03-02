import Foundation
import Network
import Security

enum ServerEvent {
    case serverStarted(httpPort: UInt16, httpsPort: UInt16)
    case serverFailed(String)
    case request(method: String, path: String, bodyPreview: String)
    case labelPreview(zpl: String, imageData: Data, printerName: String)
}

struct ServerPrinter {
    let id: UUID
    let name: String
    let labelDimensions: String
}

struct BrowserPrintDevice: Codable {
    let name: String
    let uid: String
    let connection: String
    let deviceType: String
    let provider: String
    let manufacturer: String
    let version: Int

    static func zebra(port: UInt16, printer: ServerPrinter) -> BrowserPrintDevice {
        BrowserPrintDevice(
            name: printer.name,
            uid: "\(printer.id.uuidString)@localhost:\(port)",
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
}

final class ServerController {
    private let httpPort: UInt16
    private let httpsPort: UInt16
    private let printers: [ServerPrinter]
    private let onEvent: (ServerEvent) -> Void
    private let renderer = ZPLRenderer()
    private let tlsIdentityManager = TLSIdentityManager()
    private var httpListener: NWListener?
    private var httpsListener: NWListener?
    private let stateQueue = DispatchQueue(label: "ServerController.State")
    private var httpReady = false
    private var httpsReady = false
    private var didEmitStart = false

    init(httpPort: UInt16, httpsPort: UInt16, printers: [ServerPrinter], onEvent: @escaping (ServerEvent) -> Void) {
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.printers = printers
        self.onEvent = onEvent
    }

    func start() {
        do {
            let httpNWPort = NWEndpoint.Port(rawValue: httpPort) ?? .init(integerLiteral: 9100)
            let httpsNWPort = NWEndpoint.Port(rawValue: httpsPort) ?? .init(integerLiteral: 9101)

            let httpListener = try NWListener(using: NWParameters.tcp, on: httpNWPort)
            let httpsListener = try NWListener(using: tlsParameters(), on: httpsNWPort)

            self.httpListener = httpListener
            self.httpsListener = httpsListener

            httpListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: .global(qos: .userInitiated))
                self.readRequest(on: connection, localPort: self.httpPort)
            }

            httpsListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: .global(qos: .userInitiated))
                self.readRequest(on: connection, localPort: self.httpsPort)
            }

            httpListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.markReady(isHTTPS: false)
                case .failed(let error):
                    self.onEvent(.serverFailed("HTTP \(self.httpPort): \(error.localizedDescription)"))
                default:
                    break
                }
            }

            httpsListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.markReady(isHTTPS: true)
                case .failed(let error):
                    self.onEvent(.serverFailed("HTTPS \(self.httpsPort): \(error.localizedDescription)"))
                default:
                    break
                }
            }

            httpListener.start(queue: .global(qos: .userInitiated))
            httpsListener.start(queue: .global(qos: .userInitiated))
        } catch {
            onEvent(.serverFailed(error.localizedDescription))
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
        httpListener?.cancel()
        httpsListener?.cancel()
        httpListener = nil
        httpsListener = nil
        stateQueue.sync {
            httpReady = false
            httpsReady = false
            didEmitStart = false
        }
    }

    private func markReady(isHTTPS: Bool) {
        stateQueue.sync {
            if isHTTPS {
                httpsReady = true
            } else {
                httpReady = true
            }

            guard httpReady, httpsReady, !didEmitStart else { return }
            didEmitStart = true
            onEvent(.serverStarted(httpPort: httpPort, httpsPort: httpsPort))
        }
    }

    private func readRequest(on connection: NWConnection, localPort: UInt16) {
        receiveUntilComplete(on: connection, buffer: Data()) { [weak self] data in
            guard let self, let data else {
                connection.cancel()
                return
            }

            let request = HTTPRequest.parse(data: data)
            let response = self.route(request: request, localPort: localPort)
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

    private func route(request: HTTPRequest?, localPort: UInt16) -> HTTPResponse {
        guard let request else {
            return HTTPResponse(statusCode: 400, body: "Invalid request")
        }

        let preview = String(data: request.body.prefix(240), encoding: .utf8) ?? "<binary body>"
        onEvent(.request(method: request.method, path: request.path, bodyPreview: preview))

        if request.method == "OPTIONS" {
            return HTTPResponse(statusCode: 204, body: "", additionalHeaders: corsHeaders)
        }

        let normalizedPath = request.pathWithoutQuery
        let devices = printers.map { BrowserPrintDevice.zebra(port: localPort, printer: $0) }
        switch (request.method, normalizedPath) {
        case ("GET", "/available"):
            return jsonResponse(BrowserPrintAvailableResponse(printer: devices))
        case ("GET", "/default"):
            if let first = devices.first {
                return jsonResponse(first)
            }
            return HTTPResponse(statusCode: 404, body: "No printers configured", additionalHeaders: corsHeaders)
        case ("POST", "/write"):
            handleWrite(request, localPort: localPort)
            return jsonResponse(["status": "ok", "message": "Print captured by emulator"])
        case ("GET", "/read"), ("POST", "/read"):
            return HTTPResponse(statusCode: 200, body: "", additionalHeaders: corsHeaders)
        case ("GET", "/"):
            return HTTPResponse(statusCode: 200, body: "Zebra Browser Print Emulator", additionalHeaders: corsHeaders)
        default:
            return HTTPResponse(statusCode: 404, body: "Not Found", additionalHeaders: corsHeaders)
        }
    }

    private func handleWrite(_ request: HTTPRequest, localPort: UInt16) {
        guard let payload = parseWritePayload(request) else {
            return
        }

        let zpl = payload.zpl
        let printer = resolvePrinter(for: request, localPort: localPort, targetHint: payload.targetHint)
            ?? printers.first

        guard zpl.contains("^XA") else {
            return
        }

        guard let printer else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let imageData = try? await self.renderer.render(zpl: zpl, labelDimensions: printer.labelDimensions) {
                self.onEvent(.labelPreview(zpl: zpl, imageData: imageData, printerName: printer.name))
            }
        }
    }

    private func parseWritePayload(_ request: HTTPRequest) -> (zpl: String, targetHint: String?)? {
        guard let raw = String(data: request.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if raw.first == "{",
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let zpl = extractFirstString(from: json, keys: ["zpl", "data", "body", "content"]) ?? raw
            let target = extractTargetHint(from: json)
            return (zpl, target)
        }

        return (raw, nil)
    }

    private func resolvePrinter(for request: HTTPRequest, localPort: UInt16, targetHint: String?) -> ServerPrinter? {
        let query = queryParameters(from: request.path)
        let headerMap = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.key.lowercased(), $0.value) })
        let trimmedTargetHint = targetHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let candidates: [String?] = [
            query["uid"],
            query["printer"],
            query["device"],
            query["name"],
            query["printeruid"],
            query["deviceuid"],
            query["printer_id"],
            query["printername"],
            headerMap["x-printer-uid"],
            headerMap["x-printer-name"],
            headerMap["x-browserprint-device"],
            headerMap["x-device-uid"],
            headerMap["x-device-name"]
        ]

        let hint = trimmedTargetHint.isEmpty ? candidates.first(where: { ($0 ?? "").isEmpty == false }) ?? nil : trimmedTargetHint

        if let normalized = hint?.lowercased(),
           let exact = matchPrinter(for: normalized, localPort: localPort) {
            return exact
        }

        let searchable = buildSearchableText(from: request).lowercased()
        for printer in printers {
            let uid = BrowserPrintDevice.zebra(port: localPort, printer: printer).uid.lowercased()
            if searchable.contains(uid) ||
                searchable.contains(printer.id.uuidString.lowercased()) ||
                searchable.contains(printer.name.lowercased()) {
                return printer
            }
        }

        return printers.first
    }

    private func matchPrinter(for normalizedHint: String, localPort: UInt16) -> ServerPrinter? {
        for printer in printers {
            let uid = BrowserPrintDevice.zebra(port: localPort, printer: printer).uid.lowercased()
            if uid == normalizedHint ||
                printer.id.uuidString.lowercased() == normalizedHint ||
                printer.name.lowercased() == normalizedHint {
                return printer
            }
        }
        return nil
    }

    private func extractFirstString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func extractTargetHint(from json: [String: Any]) -> String? {
        if let direct = extractFirstString(from: json, keys: ["uid", "printer", "printerName", "name", "device"]) {
            return direct
        }

        if let nested = json["device"] as? [String: Any] {
            return extractFirstString(from: nested, keys: ["uid", "name", "id"])
        }

        return nil
    }

    private func queryParameters(from path: String) -> [String: String] {
        guard let components = URLComponents(string: "http://localhost\(path)"),
              let queryItems = components.queryItems else {
            return [:]
        }

        var result: [String: String] = [:]
        for item in queryItems {
            result[item.name.lowercased()] = item.value
        }
        return result
    }

    private func buildSearchableText(from request: HTTPRequest) -> String {
        var chunks: [String] = [request.path]
        chunks.append(contentsOf: request.headers.keys)
        chunks.append(contentsOf: request.headers.values)

        if let bodyText = String(data: request.body, encoding: .utf8) {
            chunks.append(bodyText)
            if let data = bodyText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                chunks.append(contentsOf: flattenStrings(in: object))
            }
        }

        return chunks.joined(separator: "\n")
    }

    private func flattenStrings(in value: Any) -> [String] {
        if let stringValue = value as? String {
            return [stringValue]
        }

        if let dict = value as? [String: Any] {
            var results: [String] = []
            for (key, nested) in dict {
                results.append(key)
                results.append(contentsOf: flattenStrings(in: nested))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { flattenStrings(in: $0) }
        }

        return []
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
