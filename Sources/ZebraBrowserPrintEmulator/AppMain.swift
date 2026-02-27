import SwiftUI
import AppKit

@main
struct ZebraBrowserPrintEmulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        AppState.shared.startIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra("Zebra Emulator", systemImage: "printer") {
            MenuContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zebra Browser Print Emulator")
                .font(.headline)
            Text("Status: \(appState.serverStatus)")
                .font(.subheadline)
            Text("Listening on https://127.0.0.1:\(appState.port)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("Label")
                    .font(.caption)
                Picker("Label Size", selection: $appState.selectedLabelSizeKey) {
                    ForEach(appState.labelSizeKeys, id: \.self) { key in
                        Text(appState.labelSizeTitle(for: key)).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Text("Port")
                    .font(.caption)
                TextField("9100", text: $appState.portInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Apply") {
                    appState.applyPortChange()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            if let message = appState.portMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            if let summary = appState.lastRequestSummary {
                Text("Last request")
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            } else {
                Text("No requests yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 330)
        .onChange(of: appState.selectedLabelSizeKey) { newSize in
            appState.applyLabelSizeChange(newSize)
        }
    }
}
