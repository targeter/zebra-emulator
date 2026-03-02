import Foundation
import AppKit

@MainActor
final class PreviewWindowManager: NSObject {
    private struct LabelItem {
        let id: UUID
        let zpl: String
        let image: NSImage
        let printerName: String
        var payloadExpanded: Bool
    }

    private var items: [LabelItem] = []
    private var window: NSWindow?
    private var listStack: NSStackView?
    private var clearAllButton: NSButton?
    private let placementMargin: CGFloat = 16
    private let panelSize = NSSize(width: 520, height: 760)
    private static let payloadExpandedDefaultsKey = "preview.payload.expanded"
    private var defaultPayloadExpanded = UserDefaults.standard.object(forKey: payloadExpandedDefaultsKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: payloadExpandedDefaultsKey)

    func show(zpl: String, imageData: Data, printerName: String) {
        guard let image = NSImage(data: imageData) else { return }
        ensureWindow()

        items.append(
            LabelItem(id: UUID(), zpl: zpl, image: image, printerName: printerName, payloadExpanded: defaultPayloadExpanded)
        )
        rebuildList()
        if let window {
            if items.count == 1 {
                position(window: window, windowSize: panelSize)
            }
            window.orderFrontRegardless()
        }
    }

    func presentWindow() {
        ensureWindow()
        if let window {
            position(window: window, windowSize: panelSize)
            window.orderFrontRegardless()
        }
    }

    @objc
    private func removeLabel(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw) else { return }
        items.removeAll { $0.id == id }
        rebuildList()
        if items.isEmpty {
            window?.orderOut(nil)
        }
    }

    @objc
    private func clearAllLabels(_ sender: NSButton) {
        items.removeAll()
        rebuildList()
        window?.orderOut(nil)
    }

    @objc
    private func togglePayload(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].payloadExpanded.toggle()
        defaultPayloadExpanded = items[idx].payloadExpanded
        UserDefaults.standard.set(defaultPayloadExpanded, forKey: Self.payloadExpandedDefaultsKey)
        rebuildList()
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let root = NSVisualEffectView()
        root.blendingMode = .behindWindow
        root.material = .sidebar
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Label Notifications")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        let clearAll = NSButton(title: "Clear All", target: self, action: #selector(clearAllLabels(_:)))
        clearAll.bezelStyle = .rounded
        clearAll.isHidden = true
        clearAllButton = clearAll

        let header = NSStackView(views: [title, clearAll])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .equalSpacing
        header.translatesAutoresizingMaskIntoConstraints = false

        let cardsStack = NSStackView()
        cardsStack.orientation = .vertical
        cardsStack.alignment = .leading
        cardsStack.spacing = 10
        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        listStack = cardsStack

        let stackContainer = NSView()
        stackContainer.translatesAutoresizingMaskIntoConstraints = false
        stackContainer.addSubview(cardsStack)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stackContainer

        root.addSubview(header)
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            cardsStack.topAnchor.constraint(equalTo: stackContainer.topAnchor),
            cardsStack.leadingAnchor.constraint(equalTo: stackContainer.leadingAnchor),
            cardsStack.trailingAnchor.constraint(equalTo: stackContainer.trailingAnchor),
            cardsStack.bottomAnchor.constraint(equalTo: stackContainer.bottomAnchor),
            cardsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zebra Label Center"
        window.isReleasedWhenClosed = false
        window.contentView = root
        position(window: window, windowSize: panelSize)
        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
                self?.listStack = nil
                self?.clearAllButton = nil
            }
        }
    }

    private func rebuildList() {
        guard let listStack else { return }

        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in items {
            listStack.addArrangedSubview(makeCard(for: item))
        }

        clearAllButton?.isHidden = items.isEmpty
    }

    private func makeCard(for item: LabelItem) -> NSView {
        let card = NSVisualEffectView()
        card.material = .menu
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: item.printerName)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove label")?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) ?? NSImage()
        let close = NSButton(image: closeImage, target: self, action: #selector(removeLabel(_:)))
        close.bezelStyle = .circular
        close.isBordered = true
        close.imagePosition = .imageOnly
        close.contentTintColor = NSColor.secondaryLabelColor
        close.controlSize = .regular
        close.setButtonType(.momentaryPushIn)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 20),
            close.heightAnchor.constraint(equalToConstant: 20)
        ])

        let header = NSStackView(views: [title, close])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .equalSpacing
        content.addArrangedSubview(header)

        let imageView = NSImageView()
        imageView.image = item.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let fitted = fittedImageSize(item.image.size)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: fitted.width),
            imageView.heightAnchor.constraint(equalToConstant: fitted.height)
        ])
        content.addArrangedSubview(imageView)

        let toggle = NSButton(
            title: item.payloadExpanded ? "Hide ZPL payload" : "Show ZPL payload",
            target: self,
            action: #selector(togglePayload(_:))
        )
        toggle.bezelStyle = .rounded
        toggle.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        content.addArrangedSubview(toggle)

        if item.payloadExpanded {
            let payloadScroll = NSScrollView()
            payloadScroll.hasVerticalScroller = true
            payloadScroll.autohidesScrollers = true
            payloadScroll.translatesAutoresizingMaskIntoConstraints = false

            let payload = NSTextView()
            payload.isEditable = false
            payload.string = item.zpl
            payload.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            payloadScroll.documentView = payload
            NSLayoutConstraint.activate([
                payloadScroll.widthAnchor.constraint(equalToConstant: 430),
                payloadScroll.heightAnchor.constraint(equalToConstant: 105)
            ])
            content.addArrangedSubview(payloadScroll)
        }

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            card.widthAnchor.constraint(equalToConstant: 458)
        ])
        return card
    }

    private func fittedImageSize(_ source: NSSize) -> NSSize {
        let safeWidth = max(1, source.width)
        let safeHeight = max(1, source.height)
        let widthScale = 430 / safeWidth
        let heightScale = 260 / safeHeight
        let scale = min(1, widthScale, heightScale)
        let width = max(180, floor(safeWidth * scale))
        let height = max(120, floor(safeHeight * scale))
        return NSSize(width: width, height: height)
    }

    private func position(window: NSWindow, windowSize: NSSize) {
        let targetScreen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        let visible = targetScreen.visibleFrame
        let x = visible.maxX - windowSize.width - placementMargin
        let y = visible.maxY - windowSize.height - placementMargin
        let fittedX = max(visible.minX + placementMargin, x)
        let fittedY = max(visible.minY + placementMargin, y)
        window.setFrameOrigin(NSPoint(x: fittedX, y: fittedY))
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
