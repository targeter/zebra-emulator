import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStatus = "Starting"
    @Published var lastRequestSummary: String?
    @Published var portInput: String
    @Published var portMessage: String?
    @Published var selectedLabelSizeKey: String

    private(set) var port: UInt16

    private var controller: ServerController?
    private let windowManager = PreviewWindowManager()
    private var started = false
    private static let defaultPort: UInt16 = 9100
    private static let portDefaultsKey = "emulator.port"
    private static let labelSizeDefaultsKey = "emulator.label-size"

    let labelSizeKeys = ["10x5", "10x15", "10x21"]

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        let initialPort: UInt16
        if stored >= 1 && stored <= Int(UInt16.max) {
            initialPort = UInt16(stored)
        } else {
            initialPort = Self.defaultPort
        }

        let storedSize = UserDefaults.standard.string(forKey: Self.labelSizeDefaultsKey)
        let initialLabelSize = Self.labelDimensionsByKey.keys.contains(storedSize ?? "") ? (storedSize ?? "10x5") : "10x5"

        port = initialPort
        portInput = String(initialPort)
        selectedLabelSizeKey = initialLabelSize
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        startServer(on: port)
    }

    func applyPortChange() {
        let trimmed = portInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed >= 1, parsed <= Int(UInt16.max) else {
            portMessage = "Port must be between 1 and 65535."
            portInput = String(port)
            return
        }

        let newPort = UInt16(parsed)
        guard newPort != port else {
            portMessage = "Already using port \(port)."
            return
        }

        port = newPort
        UserDefaults.standard.set(Int(newPort), forKey: Self.portDefaultsKey)
        portMessage = "Restarting server on port \(newPort)..."
        controller?.stop()
        startServer(on: newPort)
    }

    func applyLabelSizeChange(_ key: String) {
        guard Self.labelDimensionsByKey[key] != nil else { return }
        selectedLabelSizeKey = key
        UserDefaults.standard.set(key, forKey: Self.labelSizeDefaultsKey)
        portMessage = "Using label size \(labelSizeTitle(for: key))."
        guard started else { return }
        controller?.stop()
        startServer(on: port)
    }

    private func startServer(on port: UInt16) {
        serverStatus = "Starting"
        let dimensions = Self.labelDimensionsByKey[selectedLabelSizeKey] ?? Self.labelDimensionsByKey["10x5"]!
        let controller = ServerController(port: port, labelDimensions: dimensions) { [weak self] event in
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

    private func handle(event: ServerEvent) {
        switch event {
        case .serverStarted(let port):
            serverStatus = "Running"
            portInput = String(port)
            portMessage = "Listening on port \(port)."
            lastRequestSummary = "Server started on port \(port)."
        case .serverFailed(let error):
            serverStatus = "Failed"
            portMessage = "Failed to bind port \(port): \(error.localizedDescription)"
            lastRequestSummary = "Server failed: \(error.localizedDescription)"
        case .request(let method, let path, let bodyPreview):
            lastRequestSummary = "\(method) \(path)\n\(bodyPreview)"
        case .labelPreview(let zpl, let imageData):
            windowManager.show(zpl: zpl, imageData: imageData)
        }
    }
}
