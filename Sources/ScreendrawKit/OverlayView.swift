import AppKit

/// The content of one overlay window: the marks of one screen, and the text field.
///
/// A thin adapter. It turns `NSEvent`s into calls on `DrawSession`, and it shows the state that
/// it reads there. Each finished mark is one layer, made one time. While the pointer drags, only
/// the path of `draftLayer` changes. The finished marks are not drawn again.
final class OverlayView: NSView, NSTextViewDelegate {
    private let display: DrawDisplay
    private let scale: CGFloat
    private let session: DrawSession

    // AppKit does not support subviews in a view that hosts its own layers. Thus the layers are in
    // `canvas`, and the text field is its sibling above it.
    private let canvas = NSView()
    /// The root of the layers. It is transparent. The tests draw this layer into a bitmap.
    let canvasLayer = CALayer()
    /// The layers of the marks. It is turned over: its sublayers have y going down, as the points of a mark.
    private let inkLayer = CALayer()
    /// The mark of the drag in progress.
    let draftLayer = CAShapeLayer()
    /// The layer of each finished mark, by the id of the mark.
    private(set) var markLayers: [Int: CALayer] = [:]
    private var shownMarksRevision = -1
    private var shownDraftRevision = -1

    /// The field of the text that is open. `nil` when the user types no text.
    private(set) var textView: NSTextView?
    private var textLayout: TextLayout?
    private var shownTextEdit: TextEdit?
    private var cursor = NSCursor.crosshair

    init(display: DrawDisplay, scale: CGFloat, session: DrawSession) {
        self.display = display
        self.scale = scale
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: display.size))
        wantsLayer = true

        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.layer = canvasLayer
        canvas.wantsLayer = true
        addSubview(canvas)

        inkLayer.actions = MarkRenderer.noActions
        inkLayer.frame = bounds
        inkLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
        canvasLayer.addSublayer(inkLayer)
        draftLayer.actions = MarkRenderer.noActions
        draftLayer.contentsScale = scale
        inkLayer.addSublayer(draftLayer)

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

    // MARK: Showing the state

    /// Shows the state of the session again. A call with no change costs two comparisons.
    func refresh() {
        if shownMarksRevision != session.marksRevision {
            shownMarksRevision = session.marksRevision
            refreshMarks()
        }
        if shownDraftRevision != session.draftRevision {
            shownDraftRevision = session.draftRevision
            if let draft = session.draft(on: display.id) {
                MarkRenderer.show(draft, in: draftLayer)
            } else if draftLayer.path != nil {
                draftLayer.path = nil
            }
        }
        refreshTextView()

        let next: NSCursor = session.pointerShape == .iBeam ? .iBeam : .crosshair
        if next !== cursor {
            cursor = next
            window?.invalidateCursorRects(for: self)
        }
    }

    /// The finished marks changed: a new mark gets a layer, and the layer of a mark that is gone
    /// is removed. A mark that stays keeps its layer.
    private func refreshMarks() {
        let marks = session.marks(on: display.id)
        var layers: [Int: CALayer] = [:]
        for placed in marks {
            layers[placed.id] = markLayers[placed.id] ?? MarkRenderer.makeLayer(for: placed.mark, scale: scale)
        }
        markLayers = layers
        // The oldest mark is at the bottom. The mark in progress is above all.
        inkLayer.sublayers = marks.compactMap { layers[$0.id] } + [draftLayer]
        refreshOpacities()
    }

    /// The timer calls this for each tick: a Fade or Hold mark gets the strength that its clock gives.
    func refreshOpacities() {
        for placed in session.marks(on: display.id) where placed.stay != .sticky {
            let opacity = Float(session.opacity(of: placed))
            if let layer = markLayers[placed.id], layer.opacity != opacity {
                layer.opacity = opacity
            }
        }
    }

    // MARK: The text field

    private func refreshTextView() {
        guard let edit = session.textEdit, edit.displayID == display.id else {
            removeTextView()
            return
        }
        if textView == nil || shownTextEdit?.origin != edit.origin {
            removeTextView()
            makeTextView(for: edit)
        } else if shownTextEdit?.style != edit.style, let textView = textView {
            apply(edit.style, to: textView)
        }
        shownTextEdit = edit
    }

    private func makeTextView(for edit: TextEdit) {
        // The same layout as `MarkRenderer`, so the lines break where the finished mark breaks them.
        let layout = TextLayout(text: "", style: edit.style, wrapWidth: edit.wrapWidth)
        // From the place of the text to the right and the bottom edge of the screen.
        let frame = CGRect(
            x: edit.origin.x,
            y: 0,
            width: edit.wrapWidth,
            height: max(bounds.height - edit.origin.y, 1)
        )
        let field = NSTextView(frame: frame, textContainer: layout.container)
        field.delegate = self
        field.drawsBackground = false
        field.isRichText = false
        field.allowsUndo = true
        field.textContainerInset = .zero
        field.isVerticallyResizable = false
        field.isHorizontallyResizable = false
        field.clipsToBounds = true
        field.focusRingType = .none
        // The user types a label, not prose. macOS must not change what was typed.
        field.isAutomaticSpellingCorrectionEnabled = false
        field.isAutomaticTextReplacementEnabled = false
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isAutomaticDashSubstitutionEnabled = false
        field.isContinuousSpellCheckingEnabled = false
        apply(edit.style, to: field)

        addSubview(field)
        textView = field
        textLayout = layout
        // The typing goes to the window that has the keyboard. The panel takes it with no app switch.
        if let window = window, window.isVisible, !window.isKeyWindow {
            window.makeKey()
        }
        window?.makeFirstResponder(field)
    }

    private func apply(_ style: MarkStyle, to field: NSTextView) {
        let attributes = MarkRenderer.textAttributes(style)
        field.font = attributes[.font] as? NSFont
        field.textColor = attributes[.foregroundColor] as? NSColor
        field.insertionPointColor = (attributes[.foregroundColor] as? NSColor) ?? .red
        field.typingAttributes = attributes
    }

    private func removeTextView() {
        guard let field = textView else { return }
        textView = nil
        textLayout = nil
        shownTextEdit = nil
        if window?.firstResponder === field {
            window?.makeFirstResponder(self)
        }
        field.delegate = nil
        field.removeFromSuperview()
    }

    func textDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextView, field === textView else { return }
        session.textChanged(field.string)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Return finishes the text. Option-Return still makes a new line.
            session.completeText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            session.escape()
            return true
        default:
            return false
        }
    }

    // MARK: Events

    // AppKit has its origin at the bottom-left. A mark has its origin at the top-left.
    private func point(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    override var acceptsFirstResponder: Bool { true }

    // A click on the overlay of a different screen must start a drag at once.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The text field takes a click on its text, to move the caret. Each other click is for the
    /// session: it draws, or it finishes the text.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let field = textView, let layout = textLayout, hit.isDescendant(of: field),
           layout.usedRect.insetBy(dx: -4, dy: -2).contains(field.convert(point, from: superview)) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        session.pointerDown(at: point(for: event), on: display.id)
    }

    override func mouseDragged(with event: NSEvent) {
        session.pointerDragged(to: point(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        session.pointerUp(at: point(for: event))
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    /// Esc. Each other key stops here: no call to super, so a key does not beep and does not go
    /// to the app below.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            session.escape()
        }
    }

    /// Command-Z and Shift-Command-Z. The app has no Edit menu, so the keys of the menu come here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command), !flags.contains(.control), !flags.contains(.option)
        else { return super.performKeyEquivalent(with: event) }
        // Some keyboard layouts give the Latin letter only in `characters`.
        let keys = [event.charactersIgnoringModifiers, event.characters].map { $0?.lowercased() }
        let isShift = flags.contains(.shift)

        if let field = textView {
            // While a text is open, the keys are for the typing.
            if keys.contains("z") {
                if isShift { field.undoManager?.redo() } else { field.undoManager?.undo() }
            } else if keys.contains("v") {
                field.pasteAsPlainText(nil)
            } else if keys.contains("c") {
                field.copy(nil)
            } else if keys.contains("x") {
                field.cut(nil)
            } else if keys.contains("a") {
                field.selectAll(nil)
            } else {
                return super.performKeyEquivalent(with: event)
            }
            return true
        }
        guard keys.contains("z") else { return super.performKeyEquivalent(with: event) }
        if isShift { session.redo() } else { session.undo() }
        return true
    }

    // MARK: The pointer shape

    // The cursor rectangle always holds the current shape, so AppKit and this view never set
    // different shapes.

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}
