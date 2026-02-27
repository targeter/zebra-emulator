import Foundation
import AppKit

@MainActor
final class PreviewWindowManager: NSObject {
    private struct WindowLayout {
        let expandedSize: NSSize
        let collapsedSize: NSSize
        let imageSize: NSSize
        let payloadWidth: CGFloat
    }

    private var windows: [NSWindow] = []
    private var payloadSections: [Int: NSView] = [:]
    private var payloadToggleButtons: [Int: NSButton] = [:]
    private var windowLayouts: [Int: WindowLayout] = [:]
    private let placementMargin: CGFloat = 16
    private static let payloadExpandedDefaultsKey = "preview.payload.expanded"
    private var isPayloadExpanded = UserDefaults.standard.object(forKey: payloadExpandedDefaultsKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: payloadExpandedDefaultsKey)

    func show(zpl: String, imageData: Data) {
        let image = NSImage(data: imageData)
        let layout = computeLayout(for: image?.size ?? NSSize(width: 320, height: 480))

        let contentView = NSStackView()
        contentView.orientation = .vertical
        contentView.alignment = .leading
        contentView.spacing = 10
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Captured ZPL label")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        contentView.addArrangedSubview(title)

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: layout.imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: layout.imageSize.height)
        ])
        contentView.addArrangedSubview(imageView)

        let zplTitle = NSTextField(labelWithString: "ZPL payload")
        zplTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let payloadToggleButton = NSButton(
            title: isPayloadExpanded ? "Hide ZPL payload" : "Show ZPL payload",
            target: self,
            action: #selector(togglePayload(_:))
        )
        payloadToggleButton.bezelStyle = .rounded

        let payloadHeader = NSStackView(views: [zplTitle, payloadToggleButton])
        payloadHeader.orientation = .horizontal
        payloadHeader.alignment = .centerY
        payloadHeader.distribution = .equalSpacing
        contentView.addArrangedSubview(payloadHeader)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let textView = NSTextView()
        textView.isEditable = false
        textView.string = zpl
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        scrollView.documentView = textView
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: layout.payloadWidth),
            scrollView.heightAnchor.constraint(equalToConstant: 150)
        ])

        let payloadSection = NSStackView(views: [scrollView])
        payloadSection.orientation = .vertical
        payloadSection.alignment = .leading
        payloadSection.isHidden = !isPayloadExpanded
        contentView.addArrangedSubview(payloadSection)

        let container = NSView()
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: isPayloadExpanded ? layout.expandedSize : layout.collapsedSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zebra Label Preview"
        window.contentView = container
        position(window: window, windowSize: isPayloadExpanded ? layout.expandedSize : layout.collapsedSize)
        window.orderFrontRegardless()
        let windowNumber = window.windowNumber
        payloadSections[windowNumber] = payloadSection
        payloadToggleButtons[windowNumber] = payloadToggleButton
        windowLayouts[windowNumber] = layout
        payloadToggleButton.tag = windowNumber
        windows.append(window)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.windows.removeAll { $0 == window }
                self?.payloadSections.removeValue(forKey: window.windowNumber)
                self?.payloadToggleButtons.removeValue(forKey: window.windowNumber)
                self?.windowLayouts.removeValue(forKey: window.windowNumber)
            }
        }
    }

    @objc
    private func togglePayload(_ sender: NSButton) {
        guard let payloadSection = payloadSections[sender.tag],
              let window = windows.first(where: { $0.windowNumber == sender.tag }),
              let layout = windowLayouts[sender.tag] else {
            return
        }
        isPayloadExpanded.toggle()
        UserDefaults.standard.set(isPayloadExpanded, forKey: Self.payloadExpandedDefaultsKey)
        applyPayloadVisibility(isPayloadExpanded, payloadSection: payloadSection, window: window, layout: layout)
        for button in payloadToggleButtons.values {
            button.title = isPayloadExpanded ? "Hide ZPL payload" : "Show ZPL payload"
        }
    }

    private func applyPayloadVisibility(_ expanded: Bool, payloadSection: NSView, window: NSWindow, layout: WindowLayout) {
        payloadSection.isHidden = !expanded
        let targetSize = expanded ? layout.expandedSize : layout.collapsedSize
        let currentFrame = window.frame
        let deltaHeight = targetSize.height - currentFrame.size.height
        let adjustedOrigin = NSPoint(x: currentFrame.origin.x, y: currentFrame.origin.y - deltaHeight)
        let newFrame = NSRect(origin: adjustedOrigin, size: targetSize)
        window.setFrame(newFrame, display: true, animate: true)
    }

    private func computeLayout(for imageSize: NSSize) -> WindowLayout {
        let safeWidth = max(1, imageSize.width)
        let safeHeight = max(1, imageSize.height)
        let widthScale = 520 / safeWidth
        let heightScale = 700 / safeHeight
        let scale = min(1, widthScale, heightScale)

        let imageWidth = max(180, floor(safeWidth * scale))
        let imageHeight = max(220, floor(safeHeight * scale))
        let contentWidth = max(imageWidth, 260)
        let windowWidth = contentWidth + 32

        let expandedHeight = imageHeight + 260
        let collapsedHeight = imageHeight + 90

        return WindowLayout(
            expandedSize: NSSize(width: windowWidth, height: expandedHeight),
            collapsedSize: NSSize(width: windowWidth, height: collapsedHeight),
            imageSize: NSSize(width: imageWidth, height: imageHeight),
            payloadWidth: contentWidth
        )
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
