import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStatus = "Starting"
    @Published var lastRequestSummary: String?
    @Published var httpPortInput: String
    @Published var httpsPortInput: String
    @Published var portMessage: String?
    @Published var selectedLabelSizeKey: String

    private(set) var httpPort: UInt16
    private(set) var httpsPort: UInt16

    private var controller: ServerController?
    private let windowManager = PreviewWindowManager()
    private var started = false
    private static let defaultHTTPPort: UInt16 = 9100
    private static let defaultHTTPSPort: UInt16 = 9101
    private static let httpPortDefaultsKey = "emulator.port"
    private static let httpsPortDefaultsKey = "emulator.https-port"
    private static let labelSizeDefaultsKey = "emulator.label-size"

    let labelSizeKeys = ["10x5", "10x15", "10x21"]

    private init() {
        let initialHTTPPort = Self.loadPort(forKey: Self.httpPortDefaultsKey, fallback: Self.defaultHTTPPort)
        let initialHTTPSPort = Self.loadPort(forKey: Self.httpsPortDefaultsKey, fallback: Self.defaultHTTPSPort)

        let storedSize = UserDefaults.standard.string(forKey: Self.labelSizeDefaultsKey)
        let initialLabelSize = Self.labelDimensionsByKey.keys.contains(storedSize ?? "") ? (storedSize ?? "10x5") : "10x5"

        httpPort = initialHTTPPort
        httpsPort = initialHTTPSPort
        httpPortInput = String(initialHTTPPort)
        httpsPortInput = String(initialHTTPSPort)
        selectedLabelSizeKey = initialLabelSize
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        startServer(httpPort: httpPort, httpsPort: httpsPort)
    }

    func applyPortChanges() {
        let trimmedHTTP = httpPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedHTTP = Int(trimmedHTTP), parsedHTTP >= 1, parsedHTTP <= Int(UInt16.max) else {
            portMessage = "HTTP port must be between 1 and 65535."
            httpPortInput = String(httpPort)
            return
        }

        let trimmedHTTPS = httpsPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedHTTPS = Int(trimmedHTTPS), parsedHTTPS >= 1, parsedHTTPS <= Int(UInt16.max) else {
            portMessage = "HTTPS port must be between 1 and 65535."
            httpsPortInput = String(httpsPort)
            return
        }

        let newHTTPPort = UInt16(parsedHTTP)
        let newHTTPSPort = UInt16(parsedHTTPS)
        guard newHTTPPort != newHTTPSPort else {
            portMessage = "HTTP and HTTPS ports must be different."
            return
        }

        guard newHTTPPort != httpPort || newHTTPSPort != httpsPort else {
            portMessage = "Already using HTTP \(httpPort) and HTTPS \(httpsPort)."
            return
        }

        httpPort = newHTTPPort
        httpsPort = newHTTPSPort
        UserDefaults.standard.set(Int(newHTTPPort), forKey: Self.httpPortDefaultsKey)
        UserDefaults.standard.set(Int(newHTTPSPort), forKey: Self.httpsPortDefaultsKey)
        portMessage = "Restarting listeners (HTTP \(newHTTPPort), HTTPS \(newHTTPSPort))..."
        controller?.stop()
        startServer(httpPort: newHTTPPort, httpsPort: newHTTPSPort)
    }

    func applyLabelSizeChange(_ key: String) {
        guard Self.labelDimensionsByKey[key] != nil else { return }
        selectedLabelSizeKey = key
        UserDefaults.standard.set(key, forKey: Self.labelSizeDefaultsKey)
        portMessage = "Using label size \(labelSizeTitle(for: key))."
        guard started else { return }
        controller?.stop()
        startServer(httpPort: httpPort, httpsPort: httpsPort)
    }

    private func startServer(httpPort: UInt16, httpsPort: UInt16) {
        serverStatus = "Starting"
        let dimensions = Self.labelDimensionsByKey[selectedLabelSizeKey] ?? Self.labelDimensionsByKey["10x5"]!
        let controller = ServerController(httpPort: httpPort, httpsPort: httpsPort, labelDimensions: dimensions) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        self.controller = controller
        controller.start()
    }

    func labelSizeTitle(for key: String) -> String {
        switch key {
        case "10x5": return "10 x 5 cm"
        case "10x15": return "10 x 15 cm"
        case "10x21": return "10 x 21 cm"
        default: return "10 x 5 cm"
        }
    }

    private static let labelDimensionsByKey: [String: String] = [
        "10x5": "3.94x1.97",
        "10x15": "3.94x5.91",
        "10x21": "3.94x8.27"
    ]

    private static func loadPort(forKey key: String, fallback: UInt16) -> UInt16 {
        let stored = UserDefaults.standard.integer(forKey: key)
        if stored >= 1 && stored <= Int(UInt16.max) {
            return UInt16(stored)
        }
        return fallback
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .serverStarted(let httpPort, let httpsPort):
            serverStatus = "Running"
            httpPortInput = String(httpPort)
            httpsPortInput = String(httpsPort)
            portMessage = "Listening on HTTP \(httpPort) and HTTPS \(httpsPort)."
            lastRequestSummary = "Server started on HTTP \(httpPort) and HTTPS \(httpsPort)."
        case .serverFailed(let details):
            serverStatus = "Failed"
            portMessage = "Failed to start listeners: \(details)"
            lastRequestSummary = "Server failed: \(details)"
        case .request(let method, let path, let bodyPreview):
            lastRequestSummary = "\(method) \(path)\n\(bodyPreview)"
        case .labelPreview(let zpl, let imageData):
            windowManager.show(zpl: zpl, imageData: imageData)
        }
    }
}
