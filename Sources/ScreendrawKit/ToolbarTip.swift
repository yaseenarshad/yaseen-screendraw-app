import AppKit

/// The tip of a toolbar button: its name and its key, for example "Arrow  A" (D16).
///
/// It is its own panel, because it shows outside the toolbar. The tooltip of macOS is not used:
/// the app is an accessory app and is usually not the active app, and then macOS can show no tooltip.
/// The tip never takes the mouse or the keyboard.
final class ToolbarTip: NSPanel {
    init(name: String, key: String) {
        let view = ToolbarTipView(name: name, key: key)
        super.init(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        collectionBehavior = OverlayWindow.allSpaces
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isFloatingPanel = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        // The same as the toolbar: out of a screen capture, and one level above the overlays.
        sharingType = .none
        contentView = view
        level = ToolbarPanel.toolbarLevel
    }
}

/// The content of the tip: the name in white and the key in grey, on the colours of the toolbar.
final class ToolbarTipView: NSView {
    private static let inset = CGSize(width: 7, height: 4)

    let text: NSAttributedString

    init(name: String, key: String) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let text = NSMutableAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.white])
        if !key.isEmpty {
            text.append(NSAttributedString(
                string: "  " + key, attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.62)]
            ))
        }
        self.text = text
        let size = text.size()
        super.init(frame: CGRect(
            x: 0, y: 0,
            width: ceil(size.width) + 2 * ToolbarTipView.inset.width,
            height: ceil(size.height) + 2 * ToolbarTipView.inset.height
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor(white: 0.13, alpha: 0.96).setFill()
        box.fill()
        NSColor(white: 1, alpha: 0.18).setStroke()
        box.lineWidth = 0.5
        box.stroke()
        text.draw(at: CGPoint(x: ToolbarTipView.inset.width, y: ToolbarTipView.inset.height))
    }
}
