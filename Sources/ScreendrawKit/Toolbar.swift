import AppKit

/// The toolbar (D5, D6). Row 1: the six tools, Undo, Redo, Clear all, and Close at the right end.
/// Row 2: the three sizes, the six colours, and the switch Fade, Hold, Sticky.
///
/// A thin adapter: a click calls `DrawSession`, and `refresh()` shows the state that it reads there.
final class Toolbar: NSView {
    private static let buttonSide: CGFloat = 28
    private static let padding: CGFloat = 4
    private static let spacing: CGFloat = 2
    private static let groupGap: CGFloat = 9
    private static let rowHeight = buttonSide + 2 * padding
    /// The room between the toolbar and the bottom of the screen.
    private static let bottomMargin: CGFloat = 24

    private let session: DrawSession
    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var sizeButtons: [MarkSize: ToolbarButton] = [:]
    private var colorButtons: [MarkColor: ToolbarButton] = [:]
    private var stayButtons: [StayMode: ToolbarButton] = [:]
    private let undoButton: ToolbarButton
    private let redoButton: ToolbarButton

    init(session: DrawSession) {
        self.session = session
        undoButton = ToolbarButton(name: "Undo", image: Toolbar.symbol("arrow.uturn.backward", name: "Undo")) {
            [session] in session.undo()
        }
        redoButton = ToolbarButton(name: "Redo", image: Toolbar.symbol("arrow.uturn.forward", name: "Redo")) {
            [session] in session.redo()
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.13, alpha: 0.96)
        layer?.cornerRadius = 8
        layer?.borderColor = CGColor(gray: 1, alpha: 0.18)
        layer?.borderWidth = 0.5

        let tools = Tool.allCases.map { tool -> ToolbarButton in
            let button = ToolbarButton(name: tool.name, image: Toolbar.symbol(Toolbar.symbolName(for: tool), name: tool.name)) {
                [session] in session.selectTool(tool)
            }
            toolButtons[tool] = button
            return button
        }
        let clear = ToolbarButton(name: "Clear all", image: Toolbar.symbol("trash", name: "Clear all")) {
            [session] in session.clearAll()
        }
        let close = ToolbarButton(name: "Close", image: Toolbar.symbol("xmark", name: "Close")) {
            [session] in session.stop()
        }
        let sizes = MarkSize.allCases.map { size -> ToolbarButton in
            let button = ToolbarButton(name: size.name, image: Toolbar.dot(for: size)) { [session] in session.setSize(size) }
            sizeButtons[size] = button
            return button
        }
        let colors = MarkColor.allCases.map { color -> ToolbarButton in
            let button = ToolbarButton(name: color.name, image: Toolbar.swatch(for: color)) { [session] in session.setColor(color) }
            colorButtons[color] = button
            return button
        }
        // The switch shows its three names, because no picture tells "Fade", "Hold" or "Sticky".
        let stays = StayMode.allCases.map { stay -> ToolbarButton in
            let button = ToolbarButton(name: stay.name, image: nil) { [session] in session.setStay(stay) }
            stayButtons[stay] = button
            return button
        }

        let firstRow = layOut([tools, [undoButton, redoButton, clear]], y: 0)
        let secondRow = layOut([sizes, colors, stays], y: Toolbar.rowHeight)
        // Close is at the right end. The free area before it is where a drag moves the toolbar.
        let width = max(firstRow + Toolbar.groupGap + Toolbar.buttonSide, secondRow)
        close.frame.origin = CGPoint(x: width - Toolbar.padding - Toolbar.buttonSide, y: Toolbar.padding)
        addSubview(close)
        setFrameSize(CGSize(width: width, height: 2 * Toolbar.rowHeight))

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // Row 1 is at the top, and row 2 is below it.
    override var isFlipped: Bool { true }

    /// Shows the state of the session: the selected tool, size, colour and stay mode.
    func refresh() {
        for (tool, button) in toolButtons { button.isOn = tool == session.tool }
        for (size, button) in sizeButtons { button.isOn = size == session.style.size }
        for (color, button) in colorButtons { button.isOn = color == session.style.color }
        for (stay, button) in stayButtons { button.isOn = stay == session.stay }
        if undoButton.isEnabled != session.canUndo { undoButton.isEnabled = session.canUndo }
        if redoButton.isEnabled != session.canRedo { redoButton.isEnabled = session.canRedo }
    }

    /// The button with the given name ("Pen", "Undo", "Thick", "Blue", "Sticky" and so on).
    func button(named name: String) -> NSButton? {
        subviews.compactMap { $0 as? ToolbarButton }.first { $0.name == name }
    }

    /// Where the toolbar shows when drawing starts: the bottom centre of the screen.
    /// `visibleFrame` is the screen with no menu bar and no Dock, in the global points of AppKit.
    static func origin(for size: CGSize, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: (visibleFrame.midX - size.width / 2).rounded(), y: visibleFrame.minY + bottomMargin)
    }

    // MARK: The buttons

    /// Puts the groups of buttons in one row, from the left. Returns the width of the row.
    private func layOut(_ groups: [[ToolbarButton]], y: CGFloat) -> CGFloat {
        var x = Toolbar.padding
        for (index, group) in groups.enumerated() {
            if index > 0 { x += Toolbar.groupGap - Toolbar.spacing }
            for button in group {
                button.frame.origin = CGPoint(x: x, y: y + Toolbar.padding)
                addSubview(button)
                x += button.frame.width + Toolbar.spacing
            }
        }
        return x - Toolbar.spacing + Toolbar.padding
    }

    // MARK: The pictures of the buttons

    private static func symbolName(for tool: Tool) -> String {
        switch tool {
        case .pen: return "pencil"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }

    private static func symbol(_ symbolName: String, name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration) {
            return image
        }
        // A system with no such symbol shows the first letter of the name.
        let letter = NSAttributedString(
            string: String(name.prefix(1)),
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.black]
        )
        let image = NSImage(size: letter.size(), flipped: false) { _ in
            letter.draw(at: .zero)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The picture of a size: a dot that grows with the size.
    private static func dot(for size: MarkSize) -> NSImage {
        let diameter = MarkStyle(color: .black, size: size).lineWidth(for: .pen) + 2
        let image = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter
            )).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The picture of a colour: a disc with a grey edge, so black and white show on the dark toolbar.
    private static func swatch(for color: MarkColor) -> NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            (NSColor(cgColor: MarkRenderer.color(color)) ?? .red).setFill()
            disc.fill()
            NSColor(white: 0.6, alpha: 1).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            return true
        }
    }

    // MARK: Events

    // A drag that starts between the buttons moves the toolbar. It makes no mark, because the
    // toolbar is its own window.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    // The pointer over the toolbar is the arrow, not the crosshair of the overlay.

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

/// One button of the toolbar: a picture or its name, and a mark when it is selected.
final class ToolbarButton: NSButton {
    let name: String
    private let onClick: () -> Void

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            layer?.backgroundColor = isOn ? CGColor(gray: 1, alpha: 0.28) : nil
        }
    }

    /// With no image, the button shows its name.
    init(name: String, image: NSImage?, onClick: @escaping () -> Void) {
        self.name = name
        self.onClick = onClick
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        isBordered = false
        if let image = image {
            self.image = image
            imagePosition = .imageOnly
            imageScaling = .scaleNone
            contentTintColor = .white
        } else {
            attributedTitle = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
            imagePosition = .noImage
            frame.size.width = ceil(attributedTitle.size().width) + 14
        }
        // The keyboard stays with the overlay, so Esc and the typing still work after a click.
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        target = self
        action = #selector(clicked)
        setAccessibilityLabel(name)
        toolTip = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func clicked() {
        onClick()
    }

    // The toolbar never has the keyboard. The first click must already press the button.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel of the toolbar: one for all screens, above the overlays. It never takes the
/// keyboard: a borderless panel refuses it, and each button works with no keyboard.
final class ToolbarPanel: NSPanel {
    let toolbarView: Toolbar

    init(session: DrawSession) {
        toolbarView = Toolbar(session: session)
        super.init(
            contentRect: CGRect(origin: .zero, size: toolbarView.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        collectionBehavior = OverlayWindow.allSpaces
        hidesOnDeactivate = false
        isFloatingPanel = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // A screen capture and a screen share leave the toolbar out, when macOS obeys this.
        sharingType = .none
        contentView = toolbarView
        // One level above the overlays. A click on an overlay brings that overlay to the front
        // of its level, and the toolbar must stay above it.
        level = .screenSaver
    }
}
