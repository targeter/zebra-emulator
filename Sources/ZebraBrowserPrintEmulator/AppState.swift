import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStatus = "Starting"
    @Published var lastRequestSummary: String?
    @Published var portInput: String
    @Published var portMessage: String?

    private(set) var port: UInt16

    private var controller: ServerController?
    private let windowManager = PreviewWindowManager()
    private var started = false
    private static let defaultPort: UInt16 = 9100
    private static let portDefaultsKey = "emulator.port"

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        let initialPort: UInt16
        if stored >= 1 && stored <= Int(UInt16.max) {
            initialPort = UInt16(stored)
        } else {
            initialPort = Self.defaultPort
        }
        port = initialPort
        portInput = String(initialPort)
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

    private func startServer(on port: UInt16) {
        serverStatus = "Starting"
        let controller = ServerController(port: port) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        self.controller = controller
        controller.start()
    }

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
