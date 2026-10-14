import AppKit

/// The content of one overlay window: the marks of one screen, the outline and the handles of
/// the selected mark, and the text field.
///
/// A thin adapter. It turns `NSEvent`s into calls on `DrawSession`, and it shows the state that
/// it reads there. Each finished mark is one layer, made one time. While the pointer drags, only
/// the path of `draftLayer` changes. While Select moves or changes a mark, only the layer of that
/// mark is made again. The other finished marks are not drawn again.
final class OverlayView: NSView, NSTextViewDelegate {
    private static let selectionColor = CGColor(srgbRed: 0.10, green: 0.55, blue: 1.0, alpha: 1)
    /// The side of a handle that the user sees. Its hit area is larger (`Mark.handleHitSide`).
    private static let handleSide: CGFloat = 7

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
    /// The curves of the Pen or Highlight line in progress. A new point adds one curve to them.
    private var draftLine = SmoothLine()
    /// The layer of each finished mark, by the id of the mark.
    private(set) var markLayers: [Int: CALayer] = [:]
    /// The mark that each layer shows. A mark that Select changed gets a new layer.
    private var shownMarks: [Int: Mark] = [:]
    private var shownMarksRevision = -1
    private var shownDraftRevision = -1

    // The outline of the selected mark: a white line with blue dashes on it, so it shows on a
    // light and on a dark screen. The handles are white squares with a blue edge.
    // These layers are turned over as `inkLayer`, and a new selection changes only their paths.
    private let selectionLayer = CALayer()
    private let outlineLayer = CAShapeLayer()
    private let dashLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private var shownSelection: Mark?

    /// The field of the text that is open. `nil` when the user types no text.
    private(set) var textView: NSTextView?
    private var textLayout: TextLayout?
    private var shownTextEdit: TextEdit?
    /// The pointer of this view now.
    private(set) var cursor = NSCursor.crosshair
    private var shownPointerShape = PointerShape.crosshair
    /// The last place of the pointer on this view. With Select, the pointer shape depends on it.
    private var pointer = CGPoint.zero

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

        selectionLayer.actions = MarkRenderer.noActions
        selectionLayer.frame = bounds
        selectionLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
        canvasLayer.addSublayer(selectionLayer)
        outlineLayer.strokeColor = .white
        dashLayer.strokeColor = OverlayView.selectionColor
        dashLayer.lineDashPattern = [4, 3]
        // The outline starts on a half point. With this phase each dash starts on a whole point,
        // so the dashes are sharp at scale 1 too.
        dashLayer.lineDashPhase = 0.5
        handlesLayer.fillColor = .white
        handlesLayer.strokeColor = OverlayView.selectionColor
        for layer in [outlineLayer, dashLayer, handlesLayer] {
            layer.actions = MarkRenderer.noActions
            layer.lineWidth = 1
            if layer !== handlesLayer { layer.fillColor = nil }
            selectionLayer.addSublayer(layer)
        }

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

    /// Shows the state of the session again. A call with no change costs a few comparisons.
    func refresh() {
        if shownMarksRevision != session.marksRevision {
            shownMarksRevision = session.marksRevision
            refreshMarks()
        }
        if shownDraftRevision != session.draftRevision {
            shownDraftRevision = session.draftRevision
            if let change = session.changedMark(on: display.id) {
                // Select moves or changes one mark: only the layer of that mark is made again.
                if let old = markLayers[change.id], shownMarks[change.id] != change.mark {
                    let layer = MarkRenderer.makeLayer(for: change.mark, scale: scale)
                    layer.opacity = old.opacity
                    inkLayer.replaceSublayer(old, with: layer)
                    markLayers[change.id] = layer
                    shownMarks[change.id] = change.mark
                }
            } else if let draft = session.draft(on: display.id) {
                MarkRenderer.show(draft, in: draftLayer, line: draftLine)
            } else if draftLayer.path != nil {
                draftLayer.path = nil
                draftLine = SmoothLine()
            }
        }
        refreshSelection()
        refreshTextView()
        refreshCursor()
    }

    /// The finished marks changed: a new mark and a mark that changed get a layer, and the layer
    /// of a mark that is gone is removed. A mark that stays the same keeps its layer.
    private func refreshMarks() {
        let marks = session.marks(on: display.id)
        let change = session.changedMark(on: display.id)
        // A text that is open again shows in its field, not as a mark.
        let openTextID = session.textEdit?.markID
        var layers: [Int: CALayer] = [:]
        var shown: [Int: Mark] = [:]
        for placed in marks {
            // During a drag of Select, the mark of the drag shows.
            let mark = placed.id == change?.id ? change?.mark ?? placed.mark : placed.mark
            let kept = shownMarks[placed.id] == mark ? markLayers[placed.id] : nil
            let layer = kept ?? MarkRenderer.makeLayer(for: mark, scale: scale)
            if layer.isHidden != (placed.id == openTextID) { layer.isHidden = placed.id == openTextID }
            layers[placed.id] = layer
            shown[placed.id] = mark
        }
        markLayers = layers
        shownMarks = shown
        // The oldest mark is at the bottom. The mark in progress is above all.
        inkLayer.sublayers = marks.compactMap { layers[$0.id] } + [draftLayer]
        refreshOpacities()
    }

    /// The outline and the handles of the selected mark. They are paths, so a new selection
    /// draws no mark again.
    private func refreshSelection() {
        let selected = session.selectedMark(on: display.id)
        guard selected != shownSelection else { return }
        shownSelection = selected
        var outline: CGPath?
        var handles: CGMutablePath?
        if let mark = selected {
            // On the middle of a pixel, so the 1 point line is sharp.
            outline = CGPath(rect: mark.outline.integral.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            let half = OverlayView.handleSide / 2
            for handle in mark.handles {
                // One square for each handle, on whole points. The 1 point edge is inside the square.
                let square = CGRect(
                    x: (handle.point.x - half).rounded(.down), y: (handle.point.y - half).rounded(.down),
                    width: OverlayView.handleSide, height: OverlayView.handleSide
                )
                if handles == nil { handles = CGMutablePath() }
                handles?.addRect(square.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        outlineLayer.path = outline
        dashLayer.path = outline
        handlesLayer.path = handles
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
        // A text that is open again starts with its old text.
        let layout = TextLayout(text: edit.text, style: edit.style, wrapWidth: edit.wrapWidth)
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
        field.setSelectedRange(NSRange(location: (edit.text as NSString).length, length: 0))

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
        let point = point(for: event)
        session.setShift(event.modifierFlags.contains(.shift))
        session.pointerDown(at: point, on: display.id)
        if event.clickCount == 2 {
            session.doubleClick(at: point, on: display.id)
        }
        showCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        session.setShift(event.modifierFlags.contains(.shift))
        session.pointerDragged(to: point(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        let point = point(for: event)
        session.pointerUp(at: point)
        showCursor(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        showCursor(at: point(for: event))
    }

    /// Shift makes a shape straight. The session gets each press and each release, so the mark
    /// of a drag changes at once (row 2.56).
    override func flagsChanged(with event: NSEvent) {
        session.setShift(event.modifierFlags.contains(.shift))
    }

    /// Esc, Delete and the keys of the toolbar. Each other key stops here: no call to super, so a
    /// key does not beep and does not go to the app below.
    ///
    /// The toolbar keys are not global hotkeys. This view exists only while drawing is on, and
    /// it gets a key only in mode drawing. In click-through and in mode off, a key goes to the
    /// app below (row 2.34).
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            session.escape()
        case 51, 117:
            // Delete and Forward Delete remove the selected mark. With no selection they clear each
            // mark, as the Clear all button does. Drawing stays on.
            // While a text is open, the text field has the keyboard, and Delete is for the typing.
            session.delete()
        default:
            // A key that stays down makes one change only (row 2.38).
            guard !event.isARepeat,
                  let key = ToolbarKeys.key(typed: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
            else { return }
            session.toolbarKey(key)
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

    // The shape tells what a drag does. The cursor rectangle always holds the current shape, so
    // AppKit and this view never set different shapes.

    private func refreshCursor() {
        let shape = session.pointerShape(at: pointer, on: display.id)
        guard shape != shownPointerShape else { return }
        shownPointerShape = shape
        cursor = OverlayView.cursor(for: shape)
        window?.invalidateCursorRects(for: self)
    }

    /// The pointer is at `point` now. Only a window on the screen sets the pointer of the Mac.
    private func showCursor(at point: CGPoint) {
        pointer = point
        refreshCursor()
        if window?.isVisible == true { cursor.set() }
    }

    private static func cursor(for shape: PointerShape) -> NSCursor {
        switch shape {
        case .crosshair: return .crosshair
        case .iBeam: return .iBeam
        case .arrow: return .arrow
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize(let handle):
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch handle {
                case .topLeft: position = .topLeft
                case .top: position = .top
                case .topRight: position = .topRight
                case .right: position = .right
                case .bottomRight: position = .bottomRight
                case .bottom: position = .bottom
                case .bottomLeft: position = .bottomLeft
                case .left: position = .left
                }
                return .frameResize(position: position, directions: .all)
            }
            // macOS 14 has no public diagonal arrows: a corner shows the crosshair.
            if handle.vertical == 0 { return .resizeLeftRight }
            return handle.horizontal == 0 ? .resizeUpDown : .crosshair
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        showCursor(at: point(for: event))
    }
}
