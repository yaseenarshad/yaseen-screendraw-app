import AppKit

/// The toolbar (D5, D6, D16). One row: the grip, the tools, Undo, Redo, Clear all, the sizes,
/// the colours, the switch Fade, Hold, Sticky, the gear and Close. At the left or the right edge
/// of a screen it is one column. `ToolbarLayout` gives the place of each button for each form.
/// Each button shows its key in its bottom right corner (D11).
///
/// A thin adapter: a click calls `DrawSession`, and `refresh()` shows the state that it reads there.
final class Toolbar: NSView {
    /// The room between the toolbar and the bottom of the screen.
    private static let bottomMargin: CGFloat = 24
    /// The pointer rests this long on a button before the tip shows (row 2.110).
    static let tipDelay: TimeInterval = 0.5

    /// The form of the toolbar. The controller sets it when the toolbar gets its place.
    var form = ToolbarForm.row {
        didSet {
            if form != oldValue { layOut() }
        }
    }
    /// Where the grip and the buttons are now.
    private(set) var layout = ToolbarLayout(form: .row, groups: [])
    /// The buttons in the order of the toolbar, group by group.
    private var groups: [[ToolbarButton]] = []

    /// The global place of the pointer. A test gives a fixed place.
    var pointer: () -> CGPoint = { NSEvent.mouseLocation }
    /// The user released the toolbar after a drag. The controller selects the form and the place.
    var onDrop: () -> Void = {}
    /// Shows the tip of a button, or no tip (`nil`). The tip is a window, so the controller shows it.
    var onTip: (ToolbarButton?) -> Void = { _ in }
    /// Exists only while the pointer rests on a button and the tip of that button does not show yet.
    private(set) var tipTimer: Timer?
    private weak var hovered: ToolbarButton?
    /// The pointer at the mouse down, from the origin of the panel. `nil` when no drag is in progress.
    private var grab: CGPoint?
    private var didMove = false

    private let session: DrawSession
    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var sizeButtons: [MarkSize: ToolbarButton] = [:]
    private var colorButtons: [MarkColor: ToolbarButton] = [:]
    private var stayButtons: [StayMode: ToolbarButton] = [:]
    private let undoButton: ToolbarButton
    private let redoButton: ToolbarButton

    /// - Parameter tools: the tool buttons. A test gives a longer list, to see the layout with more tools.
    init(session: DrawSession, tools: [Tool] = Tool.allCases) {
        self.session = session
        undoButton = ToolbarButton(name: "Undo", image: Toolbar.symbol("arrow.uturn.backward", name: "Undo")) {
            [session] in session.undo()
        }
        redoButton = ToolbarButton(name: "Redo", image: Toolbar.symbol("arrow.uturn.forward", name: "Redo")) {
            [session] in session.redo()
        }
        // The four fixed keys (row 2.32). They are not in Settings.
        undoButton.key = "⌘Z"
        redoButton.key = "⇧⌘Z"
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.13, alpha: 0.96)
        layer?.cornerRadius = 8
        layer?.borderColor = CGColor(gray: 1, alpha: 0.18)
        layer?.borderWidth = 0.5

        let tools = tools.map { tool -> ToolbarButton in
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
        // The gear pauses the pen and opens the settings window (D13).
        let settings = ToolbarButton(name: "Settings", image: Toolbar.symbol("gearshape", name: "Settings")) {
            [session] in session.openSettings()
        }
        clear.key = "⌫"
        close.key = "esc"
        settings.key = "⌘,"
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

        // The order of row 2.100. The gear is immediately before Close (row 2.40).
        groups = [tools, [undoButton, redoButton, clear], sizes, colors, stays, [settings, close]]
        groups.joined().forEach { addSubview($0) }
        layOut()

        // `activeAlways`: the app is usually not the active app, and the tip must still show (row 2.111).
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
        refresh()
        showKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // The grip is at the top-left. A second row is below the first row.
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

    /// Shows the key of each tool, size, colour and stay button (row 2.32). The keys come from the
    /// store, so the buttons show a key that the settings window changed (row 5.23).
    func showKeys() {
        let keys = session.toolbarKeys.all
        for (tool, button) in toolButtons { button.key = keys[.tool(tool)]?.uppercased() ?? "" }
        for (size, button) in sizeButtons { button.key = keys[.size(size)]?.uppercased() ?? "" }
        for (color, button) in colorButtons { button.key = keys[.color(color)]?.uppercased() ?? "" }
        for (stay, button) in stayButtons { button.key = keys[.stay(stay)]?.uppercased() ?? "" }
    }

    /// Where the toolbar shows when drawing starts: the bottom centre of the screen.
    /// `visibleFrame` is the screen with no menu bar and no Dock, in the global points of AppKit.
    static func origin(for size: CGSize, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: (visibleFrame.midX - size.width / 2).rounded(), y: visibleFrame.minY + bottomMargin)
    }

    // MARK: The layout

    /// The layout of this toolbar in a form. The controller reads the size before it selects the form.
    func layout(in form: ToolbarForm) -> ToolbarLayout {
        ToolbarLayout(form: form, groups: groups.map { $0.map { $0.frame.size } })
    }

    /// Puts each button at its place for the form, and gives the toolbar the size of the form.
    private func layOut() {
        layout = layout(in: form)
        for (group, frames) in zip(groups, layout.frames) {
            for (button, frame) in zip(group, frames) { button.frame = frame }
        }
        setFrameSize(layout.size)
        needsDisplay = true
    }

    /// The grip: six small dots at the start of the toolbar. They tell where a drag moves the toolbar.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.5).setFill()
        let columns = form.isVertical ? 3 : 2, rows = form.isVertical ? 2 : 3
        let pitch: CGFloat = 4, dot: CGFloat = 2
        let left = (layout.grip.midX - (CGFloat(columns - 1) * pitch + dot) / 2).rounded()
        let top = (layout.grip.midY - (CGFloat(rows - 1) * pitch + dot) / 2).rounded()
        for column in 0..<columns {
            for row in 0..<rows {
                NSBezierPath(ovalIn: CGRect(
                    x: left + CGFloat(column) * pitch, y: top + CGFloat(row) * pitch, width: dot, height: dot
                )).fill()
            }
        }
    }

    // MARK: The pictures of the buttons

    private static func symbolName(for tool: Tool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .highlight: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .stamp: return "1.circle.fill"
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

    // The toolbar never has the keyboard. Without this, AppKit can keep the click that starts a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // A drag that starts on the grip or between the buttons moves the toolbar (row 2.106). It
    // makes no mark, because the toolbar is its own window. The view moves the panel itself, so
    // it knows when the user releases the mouse: only then the form can change (row 2.105).

    override func mouseDown(with event: NSEvent) {
        guard let frame = window?.frame else { return }
        hideTip()
        let point = pointer()
        grab = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        didMove = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab = grab, let window = window else { return }
        let point = pointer()
        // Whole points, so the toolbar stays sharp on a screen of scale 1.
        let origin = CGPoint(x: (point.x - grab.x).rounded(), y: (point.y - grab.y).rounded())
        guard origin != window.frame.origin else { return }
        window.setFrameOrigin(origin)
        didMove = true
    }

    override func mouseUp(with event: NSEvent) {
        guard grab != nil else { return }
        grab = nil
        // A click with no move leaves the toolbar as it is.
        if didMove { onDrop() }
    }

    // MARK: The hover tip

    /// The pointer moved over the toolbar, or it left the toolbar (`nil`). The point counts from
    /// the top-left of the toolbar. The tip of a button shows after the pointer rests on it.
    func pointerMoved(to point: CGPoint?) {
        let button = point.flatMap { point in groups.joined().first { $0.frame.contains(point) } }
        guard button !== hovered else { return }
        hovered = button
        hideTip()
        guard let button = button else { return }
        let timer = Timer(timeInterval: Toolbar.tipDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tipTimer = nil
                self?.onTip(button)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tipTimer = timer
    }

    /// A click, a drag, or the end of drawing: the tip goes away, and a tip that waits does not show.
    /// The tip of the same button shows again only after the pointer left that button.
    func hideTip() {
        tipTimer?.invalidate()
        tipTimer = nil
        onTip(nil)
    }

    override func mouseExited(with event: NSEvent) {
        pointerMoved(to: nil)
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
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }
}

/// One button of the toolbar: a picture or its name, its key in the bottom right corner, and a
/// mark when it is selected.
final class ToolbarButton: NSButton {
    /// The picture or the name is this much above the middle, so the key below it does not touch it.
    fileprivate static let lift: CGFloat = 3

    let name: String
    private let onClick: () -> Void

    /// The key as the button shows it: "W", "⌘Z", "esc". An empty text shows nothing.
    var key = "" {
        didSet {
            if key != oldValue { needsDisplay = true }
        }
    }

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            layer?.backgroundColor = isOn ? CGColor(gray: 1, alpha: 0.28) : nil
            // The key is lighter on the light background of the selected button.
            needsDisplay = true
        }
    }

    // The cell draws the picture and the name above the middle.
    override class var cellClass: AnyClass? {
        get { ToolbarButtonCell.self }
        set {}
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func clicked() {
        // A click removes the tip (row 2.110).
        (superview as? Toolbar)?.hideTip()
        onClick()
    }

    // The toolbar never has the keyboard. The first click must already press the button.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: The key

    /// The key is small and grey, as in the draw app (row 2.32). It is lighter on a selected
    /// button, and weaker on a button that is not available.
    var keyText: NSAttributedString {
        let strength: CGFloat = !isEnabled ? 0.3 : (isOn ? 0.9 : 0.62)
        return NSAttributedString(string: key, attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: strength),
        ])
    }

    /// Where the key is: the bottom right corner of the button. The button counts from its top.
    var keyFrame: CGRect {
        let size = keyText.size()
        return CGRect(x: bounds.maxX - size.width - 2.5, y: bounds.maxY - size.height - 0.5, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !key.isEmpty { keyText.draw(at: keyFrame.origin) }
    }
}

/// Draws the picture or the name of a `ToolbarButton` above the middle of the button.
private final class ToolbarButtonCell: NSButtonCell {
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        super.drawImage(image, withFrame: frame.offsetBy(dx: 0, dy: -ToolbarButton.lift), in: controlView)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        super.drawTitle(title, withFrame: frame.offsetBy(dx: 0, dy: -ToolbarButton.lift), in: controlView)
    }
}

/// The panel of the toolbar: one for all screens, above the overlays. It never takes the
/// keyboard: a borderless panel refuses it, and each button works with no keyboard.
final class ToolbarPanel: NSPanel {
    /// One level above the overlays. A click on an overlay brings that overlay to the front
    /// of its level, and the toolbar must stay above it. It is still below the freeze of
    /// Yaseen Screenshot.
    static let toolbarLevel = NSWindow.Level(rawValue: OverlayWindow.overlayLevel.rawValue + 1)

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
        level = ToolbarPanel.toolbarLevel
    }

    /// Gives the toolbar a form and a place. The panel has the size of the form.
    func place(_ form: ToolbarForm, at origin: CGPoint) {
        toolbarView.form = form
        setFrame(CGRect(origin: origin, size: toolbarView.layout.size), display: true)
    }
}
