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
            Text("HTTP:  http://127.0.0.1:\(appState.httpPort)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("HTTPS: https://127.0.0.1:\(appState.httpsPort)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
            Text("Printers")
                .font(.subheadline.weight(.semibold))
            ForEach(appState.printers) { printer in
                PrinterRowView(printer: printer)
                    .environmentObject(appState)
            }

            Divider()
            HStack(spacing: 8) {
                Text("HTTP")
                    .font(.caption)
                TextField("9100", text: $appState.httpPortInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("HTTPS")
                    .font(.caption)
                TextField("9101", text: $appState.httpsPortInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Apply Ports") {
                    appState.applyPortChanges()
                }
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
            HStack {
                Button("Add Printer") {
                    appState.addPrinter()
                }
                Button("Show Labels") {
                    appState.showLabelWindow()
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
    }
}

private struct PrinterRowView: View {
    @EnvironmentObject private var appState: AppState
    let printer: AppState.PrinterConfig
    @State private var draftName: String

    init(printer: AppState.PrinterConfig) {
        self.printer = printer
        _draftName = State(initialValue: printer.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Printer name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        appState.updatePrinterName(id: printer.id, name: draftName)
                    }
                Button("Save") {
                    appState.updatePrinterName(id: printer.id, name: draftName)
                }
                Button("Remove") {
                    appState.removePrinter(id: printer.id)
                }
            }

            HStack(spacing: 8) {
                Text("Paper")
                    .font(.caption)
                Picker("Paper", selection: Binding(
                    get: { printer.labelSizeKey },
                    set: { appState.updatePrinterLabelSize(id: printer.id, key: $0) }
                )) {
                    ForEach(appState.labelSizeKeys, id: \.self) { key in
                        Text(appState.labelSizeTitle(for: key)).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: printer.name) { newName in
            if newName != draftName {
                draftName = newName
            }
        }
    }
}
