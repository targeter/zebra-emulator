import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    struct PrinterConfig: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var labelSizeKey: String
    }

    @Published var serverStatus = "Starting"
    @Published var lastRequestSummary: String?
    @Published var httpPortInput: String
    @Published var httpsPortInput: String
    @Published var portMessage: String?
    @Published var printers: [PrinterConfig]

    private(set) var httpPort: UInt16
    private(set) var httpsPort: UInt16

    private var controller: ServerController?
    private let windowManager = PreviewWindowManager()
    private var started = false
    private static let defaultHTTPPort: UInt16 = 9100
    private static let defaultHTTPSPort: UInt16 = 9101
    private static let httpPortDefaultsKey = "emulator.port"
    private static let httpsPortDefaultsKey = "emulator.https-port"
    private static let printersDefaultsKey = "emulator.printers"
    private static let labelSizeDefaultsKey = "emulator.label-size"

    let labelSizeKeys = ["10x5", "10x15", "10x21"]

    private init() {
        let initialHTTPPort = Self.loadPort(forKey: Self.httpPortDefaultsKey, fallback: Self.defaultHTTPPort)
        let initialHTTPSPort = Self.loadPort(forKey: Self.httpsPortDefaultsKey, fallback: Self.defaultHTTPSPort)
        let initialPrinters = Self.loadPrinters()

        httpPort = initialHTTPPort
        httpsPort = initialHTTPSPort
        httpPortInput = String(initialHTTPPort)
        httpsPortInput = String(initialHTTPSPort)
        printers = initialPrinters
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
        restartServer(message: "Restarting listeners (HTTP \(newHTTPPort), HTTPS \(newHTTPSPort))...")
    }

    func addPrinter() {
        let nextIndex = (printers.map { Self.trailingNumber(in: $0.name) }.compactMap { $0 }.max() ?? 0) + 1
        printers.append(PrinterConfig(id: UUID(), name: "Printer \(nextIndex)", labelSizeKey: "10x5"))
        persistPrinters()
        restartServer(message: "Added printer Printer \(nextIndex).")
    }

    func removePrinter(id: UUID) {
        guard printers.count > 1 else {
            portMessage = "At least one printer must remain."
            return
        }
        printers.removeAll { $0.id == id }
        persistPrinters()
        restartServer(message: "Removed printer.")
    }

    func updatePrinterName(id: UUID, name: String) {
        guard let index = printers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        printers[index].name = trimmed.isEmpty ? "Printer" : trimmed
        persistPrinters()
        restartServer(message: "Updated printer names.")
    }

    func updatePrinterLabelSize(id: UUID, key: String) {
        guard Self.labelDimensionsByKey[key] != nil,
              let index = printers.firstIndex(where: { $0.id == id }) else { return }
        printers[index].labelSizeKey = key
        persistPrinters()
        restartServer(message: "Updated printer paper sizes.")
    }

    func showLabelWindow() {
        windowManager.presentWindow()
    }

    private func startServer(httpPort: UInt16, httpsPort: UInt16) {
        serverStatus = "Starting"
        let serverPrinters = printers.map {
            ServerPrinter(id: $0.id, name: $0.name, labelDimensions: Self.labelDimensionsByKey[$0.labelSizeKey] ?? "3.94x1.97")
        }
        let controller = ServerController(httpPort: httpPort, httpsPort: httpsPort, printers: serverPrinters) { [weak self] event in
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

    private func restartServer(message: String) {
        portMessage = message
        guard started else { return }
        controller?.stop()
        startServer(httpPort: httpPort, httpsPort: httpsPort)
    }

    private func persistPrinters() {
        if let data = try? JSONEncoder().encode(printers) {
            UserDefaults.standard.set(data, forKey: Self.printersDefaultsKey)
        }
    }

    private static func loadPrinters() -> [PrinterConfig] {
        if let data = UserDefaults.standard.data(forKey: Self.printersDefaultsKey),
           let decoded = try? JSONDecoder().decode([PrinterConfig].self, from: data) {
            let normalized = decoded.map { printer in
                PrinterConfig(
                    id: printer.id,
                    name: printer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Printer" : printer.name,
                    labelSizeKey: Self.labelDimensionsByKey[printer.labelSizeKey] == nil ? "10x5" : printer.labelSizeKey
                )
            }
            if !normalized.isEmpty {
                return normalized
            }
        }

        let legacySize = UserDefaults.standard.string(forKey: Self.labelSizeDefaultsKey)
        let initialSize = Self.labelDimensionsByKey.keys.contains(legacySize ?? "") ? (legacySize ?? "10x5") : "10x5"
        return [PrinterConfig(id: UUID(), name: "Printer 1", labelSizeKey: initialSize)]
    }

    private static func trailingNumber(in value: String) -> Int? {
        let digits = value.reversed().prefix { $0.isNumber }.reversed()
        guard !digits.isEmpty else { return nil }
        return Int(String(digits))
    }

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
        case .labelPreview(let zpl, let imageData, let printerName):
            windowManager.show(zpl: zpl, imageData: imageData, printerName: printerName)
        }
    }
}
