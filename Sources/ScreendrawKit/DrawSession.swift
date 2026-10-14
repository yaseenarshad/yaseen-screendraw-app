import CoreGraphics
import Foundation

/// A screen, as the session knows it: its id and its size in points.
struct DrawDisplay: Equatable {
    let id: CGDirectDisplayID
    let size: CGSize
}

/// A finished mark on its screen.
struct PlacedMark: Equatable {
    let id: Int
    let displayID: CGDirectDisplayID
    /// The Select tool changes it: a move, a size change, a new style or a new text.
    var mark: Mark
    /// The value of the switch when the mark was drawn. A later change of the switch does not change it.
    let stay: StayMode
    /// Only for Fade: the Fade seconds when the mark was drawn. A later change in Settings does
    /// not change it (row 3.25).
    let fadeTime: TimeInterval
    /// When the mark was finished, or when Undo or Redo brought it back. The clock of a Fade mark starts here.
    var shownAt: TimeInterval
}

/// A text that the user types now. It is not a mark yet.
struct TextEdit: Equatable {
    let displayID: CGDirectDisplayID
    /// The top-left of the text, in the points of the screen.
    let origin: CGPoint
    /// A line breaks at this width: the right edge of the screen.
    let wrapWidth: CGFloat
    var style: MarkStyle
    var text: String
    /// The id of the Text mark that is open again (row 2.85). `nil` for a new text.
    var markID: Int?
}

/// The pointer shape of the overlay. It tells what a drag from the place of the pointer does.
enum PointerShape: Equatable {
    /// A drag draws a mark, or moves an end of a Line or an Arrow.
    case crosshair
    /// A click puts a text.
    case iBeam
    /// Select, and no mark is below the pointer.
    case arrow
    /// Select: a drag moves the mark below the pointer.
    case openHand
    /// A mark moves now.
    case closedHand
    /// Select: a drag changes the size of the selected Rectangle or Ellipse.
    case resize(Handle)
}

/// The state of the drawing part, with no window and no view (D4, D5, D6, D14, D15).
///
/// It holds the mode, the marks of each screen, the tool, the size, the colour, the stay mode,
/// the selected mark, the Undo and Redo history, and the clocks of Fade and Hold. One instance
/// serves all screens. The views are thin adapters: they turn `NSEvent`s into these calls and
/// show what they read here. Every point is in the points of its screen, with the origin at the
/// top-left of that screen. The time comes from `now`, so a test sets the clock and never sleeps.
final class DrawSession {
    /// The start value of Fade seconds: a Fade mark is gone this long after it is finished.
    static let fadeTime = TimeInterval(DrawPrefs.firstFadeSeconds)
    /// The start value of Hold seconds: the Hold marks stay at full strength this long after
    /// the last drawing activity.
    static let holdTime = TimeInterval(DrawPrefs.firstHoldSeconds)
    /// A mark that goes away takes this long to fade.
    static let fadeOutTime: TimeInterval = 1
    /// The number of steps that Undo can take back.
    static let historyLimit = 200
    /// A Rectangle, an Ellipse, a Line or an Arrow smaller than this makes no mark.
    static let minimumShape = Mark.minimumSide
    /// With Select, a pointer that moved less than this is a click, not a drag.
    static let minimumDrag: CGFloat = 3

    private(set) var mode = DrawMode.off
    /// The screens that have an overlay. Empty while the mode is off.
    private(set) var displays: [DrawDisplay] = []
    private(set) var tool: Tool
    /// The stay mode of the next mark.
    private(set) var stay: StayMode
    /// The text that is open, if the user types one now.
    private(set) var textEdit: TextEdit?
    /// The id of the mark that is selected with Select.
    private(set) var selectedID: Int?
    /// Goes up each time the finished marks change. A view makes its mark layers again only then.
    private(set) var marksRevision = 0
    /// Goes up each time the mark of the drag in progress changes.
    private(set) var draftRevision = 0
    /// True while a Fade or Hold mark exists. Only then a timer must call `tick()`.
    private(set) var hasTimedMarks = false

    /// Called after something that the views show changed.
    var onChange: (() -> Void)?

    /// The keys of the toolbar, on the `UserDefaults` of the other settings. The session keeps no
    /// copy: it reads them when a key arrives, so a change in the settings window works at once.
    let toolbarKeys: ToolbarKeys

    /// One step of the history.
    private enum Step {
        case add(PlacedMark)
        /// Clear all, or the clear of Esc: all marks of all screens in one step.
        case clear([PlacedMark])
        /// Select: a move, a size change, a new style or a new text of one mark.
        case change(PlacedMark, to: Mark)
        /// Select: a delete of one mark. `index` is its place among the marks of its screen.
        case remove(PlacedMark, index: Int)

        /// The id of the one mark of the step.
        var markID: Int? {
            switch self {
            case .add(let mark), .change(let mark, _), .remove(let mark, _): return mark.id
            case .clear: return nil
            }
        }
    }

    /// The drag in progress.
    private struct Drag {
        enum Kind {
            /// The drag draws a new mark. `stay` is the value of the switch at the pointer down.
            case draw(stay: StayMode)
            /// Select: the drag moves a mark.
            case move(PlacedMark)
            /// Select: the drag moves a handle. `offset` is from the handle to the pointer, so the
            /// handle does not jump to the pointer.
            case resize(PlacedMark, MarkHandle, offset: CGPoint)
        }

        let kind: Kind
        let display: DrawDisplay
        let start: CGPoint
        /// Select: false until the pointer moved `minimumDrag` points.
        var isPastMinimum = false
    }

    private let prefs: DrawPrefs
    private let now: () -> TimeInterval
    /// The size and the colour of the next mark. One value for all tools and all screens.
    private var nextStyle: MarkStyle
    private var marksByDisplay: [CGDirectDisplayID: [PlacedMark]] = [:]
    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    private var drag: Drag?
    /// The mark of the drag in progress: the new mark with each point of the pointer, or the
    /// mark that Select changes. The list of marks changes one time, at the release. Thus one
    /// drag is one Undo step.
    private var draft: Mark?
    private var isShiftDown = false
    /// The last pointer down, drag or pointer up of a mark. The clock of the Hold marks starts here.
    private var lastActivity: TimeInterval = 0
    private var nextID = 1

    init(prefs: DrawPrefs, now: @escaping () -> TimeInterval) {
        self.prefs = prefs
        self.now = now
        toolbarKeys = ToolbarKeys(defaults: prefs.defaults)
        tool = prefs.tool
        nextStyle = MarkStyle(color: prefs.color, size: prefs.size)
        stay = prefs.stay
    }

    // MARK: What the views read

    /// The finished marks of one screen, the oldest first.
    func marks(on displayID: CGDirectDisplayID) -> [PlacedMark] {
        marksByDisplay[displayID] ?? []
    }

    /// The number of finished marks on all screens.
    var markCount: Int {
        marksByDisplay.values.reduce(0) { $0 + $1.count }
    }

    /// The new mark of the drag in progress, if it is on the given screen. With Shift, it is
    /// the straight form of the mark (rows 2.53 to 2.55).
    func draft(on displayID: CGDirectDisplayID) -> Mark? {
        guard let drag = drag, drag.display.id == displayID, case .draw = drag.kind, let mark = draft else { return nil }
        return shaped(mark, on: drag.display)
    }

    /// Select: the mark that a drag moves or changes now, as it shows during the drag, if it is
    /// on the given screen.
    func changedMark(on displayID: CGDirectDisplayID) -> (id: Int, mark: Mark)? {
        guard let drag = drag, drag.display.id == displayID, let mark = draft else { return nil }
        switch drag.kind {
        case .move(let placed), .resize(let placed, _, _): return (placed.id, mark)
        case .draw: return nil
        }
    }

    /// The selected mark as it shows now, if it is on the given screen. The overlay draws its
    /// outline and its handles. A text that is open again shows no outline.
    func selectedMark(on displayID: CGDirectDisplayID) -> Mark? {
        guard textEdit == nil, let selected = selected, selected.displayID == displayID else { return nil }
        return changedMark(on: displayID)?.mark ?? selected.mark
    }

    /// The size and the colour that the toolbar shows: of the open text, else of the selected
    /// mark, else of the next mark.
    var style: MarkStyle {
        textEdit?.style ?? selected?.mark.style ?? nextStyle
    }

    var canUndo: Bool {
        !undoSteps.isEmpty || draft != nil || textEdit != nil
    }

    var canRedo: Bool {
        !redoSteps.isEmpty
    }

    /// What a drag from `point` does, for the shape of the pointer.
    func pointerShape(at point: CGPoint, on displayID: CGDirectDisplayID) -> PointerShape {
        guard tool == .select else { return tool == .text ? .iBeam : .crosshair }
        switch drag?.kind {
        case .move?: return .closedHand
        case .resize(_, let handle, _)?: return DrawSession.pointerShape(for: handle)
        default: break
        }
        if let selected = selected, selected.displayID == displayID, let handle = selected.mark.handle(at: point) {
            return DrawSession.pointerShape(for: handle.key)
        }
        return topMark(at: point, in: marks(on: displayID)) == nil ? .arrow : .openHand
    }

    private static func pointerShape(for handle: MarkHandle) -> PointerShape {
        switch handle {
        case .frame(let handle): return .resize(handle)
        case .end: return .crosshair
        }
    }

    /// How strong a mark shows now: 1 is full strength, 0 is gone.
    func opacity(of mark: PlacedMark) -> CGFloat {
        switch mark.stay {
        case .sticky:
            return 1
        case .fade:
            // The last second of the time of a Fade mark is its fade (row 3.23).
            return DrawSession.strength(after: now() - mark.shownAt, fullFor: mark.fadeTime - DrawSession.fadeOutTime)
        case .hold:
            // The Hold marks have one common clock, so a new value in Settings applies at once (row 3.25).
            return DrawSession.strength(after: now() - lastActivity, fullFor: TimeInterval(prefs.holdSeconds))
        }
    }

    private static func strength(after elapsed: TimeInterval, fullFor full: TimeInterval) -> CGFloat {
        CGFloat(min(max(1 - (elapsed - full) / fadeOutTime, 0), 1))
    }

    // MARK: The modes

    /// The draw hotkey when the mode is off. The Sticky marks that the session kept show again.
    func start(displays newDisplays: [DrawDisplay], clickThrough: Bool = false) {
        guard mode == .off else { return }
        // "Show toolbar" starts with the pen paused: the toolbar shows, and the screen works as usual (D18).
        mode = clickThrough ? .clickThrough : .drawing
        displays = newDisplays
        dropMarksOfMissingDisplays()
        marksChanged()
    }

    /// The draw hotkey when drawing is on, and the Close button. The Sticky marks stay in
    /// memory. The Fade and Hold marks are dropped. The selection goes away (row 2.88).
    func stop() {
        guard mode != .off else { return }
        finishInProgress()
        selectedID = nil
        dropMarks { $0.stay != .sticky }
        mode = .off
        displays = []
        marksChanged()
    }

    /// The click-through hotkey while drawing is on. In mode off, the controller starts the session
    /// with the pen paused (row 4.26). The selection goes away (row 2.88).
    func toggleClickThrough() {
        guard mode != .off else { return }
        finishInProgress()
        selectedID = nil
        mode = mode == .drawing ? .clickThrough : .drawing
        onChange?()
    }

    // MARK: The gear (D13)

    /// What opens the settings window. The shell sets it. The session does not know that window.
    var onOpenSettings: () -> Void = {}

    /// The gear button of the toolbar, and Command-comma. A text or a drag in progress is finished
    /// first. Mode drawing changes to click-through, so the marks stay and the settings window
    /// gets the mouse and the keyboard. Then the settings window opens (rows 2.41 to 2.44).
    func openSettings() {
        guard mode != .off else { return }
        finishInProgress()
        if mode == .drawing {
            mode = .clickThrough
            onChange?()
        }
        onOpenSettings()
    }

    /// Esc. It arrives only in mode drawing, because only then the overlay has the keyboard.
    func escape() {
        guard mode == .drawing else { return }
        // Esc removes the text that is not finished, and drawing stays on. A text that was open
        // again keeps its old text.
        if let edit = textEdit {
            textEdit = nil
            if edit.markID == nil { onChange?() } else { marksChanged() }
            return
        }
        finishDrag()
        // With a selected mark, Esc removes only the selection (row 2.87).
        if selectedID != nil {
            selectedID = nil
            onChange?()
            return
        }
        if clearMarks() { redoSteps = [] }
        mode = .off
        displays = []
        onChange?()
    }

    /// A monitor was connected or removed while drawing is on. The marks of a removed screen
    /// are dropped. The other marks stay.
    func setDisplays(_ newDisplays: [DrawDisplay]) {
        guard mode != .off, newDisplays != displays else { return }
        finishInProgress()
        displays = newDisplays
        dropMarksOfMissingDisplays()
        marksChanged()
    }

    // MARK: The pointer

    func pointerDown(at point: CGPoint, on displayID: CGDirectDisplayID) {
        guard mode == .drawing, let display = displays.first(where: { $0.id == displayID }) else { return }
        // A click in a different place finishes the text that is open.
        finishInProgress()
        if tool == .select {
            // Select draws nothing, so it is no drawing activity: the clocks do not start again (row 2.90).
            takeMark(at: point, on: display)
            return
        }
        lastActivity = now()
        let place = nextStyle.pointOnScreen(point, for: tool, in: display.size)
        switch tool {
        case .text:
            beginText(at: point, on: display)
        case .stamp:
            // A click puts the stamp. A drag does nothing more.
            add(Mark(tool: .stamp, style: nextStyle, points: [place], number: nextStampNumber), on: display.id, stay: stay)
            marksChanged()
        default:
            drag = Drag(kind: .draw(stay: stay), display: display, start: point)
            draft = Mark(tool: tool, style: nextStyle, points: [place])
            draftChanged()
        }
    }

    func pointerDragged(to point: CGPoint) {
        guard var drag = drag else { return }
        // The mark stays on the screen of the pointer down, also when the pointer leaves that screen.
        let size = drag.display.size
        switch drag.kind {
        case .draw:
            guard let mark = draft else { return }
            lastActivity = now()
            switch mark.tool {
            case .pen, .highlight:
                let next = mark.style.pointOnScreen(point, for: mark.tool, in: size)
                guard mark.points.last != next else { return }
                draft?.points.append(next)
            default:
                // The draft has the pointer as it is, also off the screen. `shaped` keeps the mark on the screen.
                guard mark.points.count < 2 || mark.points[1] != point else { return }
                draft?.points = [mark.points[0], point]
            }
            draftChanged()
        case .move(let placed), .resize(let placed, _, _):
            if !drag.isPastMinimum {
                // A small move of the hand during a click changes nothing. It only selects.
                guard hypot(point.x - drag.start.x, point.y - drag.start.y) >= DrawSession.minimumDrag else { return }
                drag.isPastMinimum = true
                self.drag = drag
            }
            let changed: Mark
            if case .resize(_, let handle, let offset) = drag.kind {
                changed = placed.mark.resized(handle, to: CGPoint(x: point.x - offset.x, y: point.y - offset.y), in: size)
            } else {
                changed = placed.mark.moved(by: CGPoint(x: point.x - drag.start.x, y: point.y - drag.start.y), in: size)
            }
            guard draft != changed else { return }
            draft = changed
            draftChanged()
        }
    }

    func pointerUp(at point: CGPoint) {
        pointerDragged(to: point)
        finishDrag()
    }

    /// A double-click. With Select, it opens the text of a Text mark again (row 2.85).
    /// The view calls it after the second pointer down.
    func doubleClick(at point: CGPoint, on displayID: CGDirectDisplayID) {
        guard mode == .drawing, tool == .select,
              let placed = topMark(at: point, in: marks(on: displayID)),
              placed.mark.tool == .text, let origin = placed.mark.points.first
        else { return }
        // The second pointer down of the double-click started a drag of the mark. It ends here.
        drag = nil
        draft = nil
        selectedID = placed.id
        textEdit = TextEdit(
            displayID: displayID, origin: origin, wrapWidth: placed.mark.wrapWidth,
            style: placed.mark.style, text: placed.mark.text, markID: placed.id
        )
        // The text shows in its field now, not as a mark.
        marksChanged()
    }

    /// The view tells each change of the Shift key. During a drag that draws, the mark changes
    /// at once (row 2.56).
    func setShift(_ isDown: Bool) {
        guard isDown != isShiftDown else { return }
        isShiftDown = isDown
        if case .draw? = drag?.kind { draftChanged() }
    }

    // MARK: The toolbar and the keys

    /// A click on a tool. In click-through it also goes back to mode drawing.
    /// A different tool removes the selection (row 2.88).
    func selectTool(_ newTool: Tool) {
        finishInProgress()
        if newTool != .select { selectedID = nil }
        tool = newTool
        prefs.tool = newTool
        if mode == .clickThrough { mode = .drawing }
        onChange?()
    }

    /// The colour of the next mark, and of the selected mark (row 2.84). A mark that exists and
    /// is not selected does not change.
    func setColor(_ color: MarkColor) {
        prefs.color = color
        restyle { $0.color = color }
    }

    /// The size of the line, of the font of a text, or of a stamp. The same targets as `setColor`.
    func setSize(_ size: MarkSize) {
        prefs.size = size
        restyle { $0.size = size }
    }

    private func restyle(_ change: (inout MarkStyle) -> Void) {
        change(&nextStyle)
        if var edit = textEdit {
            // A text that is open is not a mark yet, so it gets the new style.
            change(&edit.style)
            textEdit = edit
        } else if drag == nil, let selected = selected, let display = displays.first(where: { $0.id == selected.displayID }) {
            var mark = selected.mark
            change(&mark.style)
            // A thicker line or a larger font can reach past an edge. The mark stays on its screen.
            if replace(selected, with: mark.moved(by: .zero, in: display.size)) {
                marksChanged()
                return
            }
        }
        onChange?()
    }

    /// The switch Fade, Hold, Sticky. A mark that exists keeps its value, also the selected
    /// mark (rows 3.7 and 2.91).
    func setStay(_ newStay: StayMode) {
        stay = newStay
        prefs.stay = newStay
        onChange?()
    }

    /// A key that the overlay got (D11). A toolbar key does the same as a click on its button.
    ///
    /// A key during a drag does nothing: the mark in progress keeps its tool and its style (row 2.37).
    /// While a text is open, the text field has the keyboard and each key is for the typing (row 2.33).
    func toolbarKey(_ key: String) {
        guard mode == .drawing, drag == nil, textEdit == nil, let action = toolbarKeys.action(for: key) else { return }
        switch action {
        case .tool(let tool): selectTool(tool)
        case .size(let size): setSize(size)
        case .color(let color): setColor(color)
        case .stay(let stay): setStay(stay)
        }
    }

    /// Takes back the newest step. A text that is open is finished first, and then it is the newest step.
    func undo() {
        finishInProgress()
        guard let step = undoSteps.popLast() else { return }
        switch step {
        case .add(let mark):
            marksByDisplay[mark.displayID]?.removeAll { $0.id == mark.id }
        case .clear(let marks):
            // The cleared marks come back below the marks that are newer than the clear.
            for (displayID, group) in Dictionary(grouping: bringBack(marks), by: { $0.displayID }) {
                marksByDisplay[displayID] = group + (marksByDisplay[displayID] ?? [])
            }
        case .change(let before, _):
            setMark(before.mark, of: before)
        case .remove(let mark, let index):
            // The mark comes back at its old place among the marks of its screen.
            let marks = marksByDisplay[mark.displayID] ?? []
            marksByDisplay[mark.displayID, default: []].insert(bringBack([mark])[0], at: min(index, marks.count))
        }
        redoSteps.append(step)
        marksChanged()
    }

    /// Does the step again that the last Undo took back.
    func redo() {
        finishInProgress()
        guard let step = redoSteps.popLast() else { return }
        switch step {
        case .add(let mark):
            let shown = bringBack([mark])[0]
            marksByDisplay[shown.displayID, default: []].append(shown)
            push(.add(shown))
        case .clear:
            clearMarks()
            return
        case .change(let before, let after):
            setMark(after, of: before)
            push(step)
        case .remove(let mark, _):
            marksByDisplay[mark.displayID]?.removeAll { $0.id == mark.id }
            push(step)
        }
        marksChanged()
    }

    /// The Clear all button and the menu row: each mark on each screen goes away. One Undo brings them back.
    func clearAll() {
        finishInProgress()
        if clearMarks() { redoSteps = [] }
    }

    /// Delete and Forward Delete. With a selected mark, only that mark goes away (row 2.86).
    /// With no selection, each mark goes away, as with the Clear all button (row 2.20).
    func delete() {
        finishInProgress()
        if let selected = selected {
            remove(selected)
            marksChanged()
        } else if clearMarks() {
            redoSteps = []
        }
    }

    // MARK: The selected mark

    /// The selected mark, as it is in the list of marks.
    private var selected: PlacedMark? {
        placed(selectedID)
    }

    /// The finished mark with the given id.
    private func placed(_ id: Int?) -> PlacedMark? {
        guard let id = id else { return nil }
        for marks in marksByDisplay.values {
            if let placed = marks.first(where: { $0.id == id }) { return placed }
        }
        return nil
    }

    /// Select: a pointer down takes a handle of the selected mark, else the mark at the point.
    /// A drag then changes that mark. A pointer down on an empty place removes the selection (row 2.81).
    private func takeMark(at point: CGPoint, on display: DrawDisplay) {
        if let selected = selected, selected.displayID == display.id, let handle = selected.mark.handle(at: point) {
            let offset = CGPoint(x: point.x - handle.point.x, y: point.y - handle.point.y)
            drag = Drag(kind: .resize(selected, handle.key, offset: offset), display: display, start: point)
            return
        }
        let hit = topMark(at: point, in: marks(on: display.id))
        if let hit = hit {
            drag = Drag(kind: .move(hit), display: display, start: point)
        }
        if hit?.id != selectedID {
            selectedID = hit?.id
            onChange?()
        }
    }

    /// A change of one mark as one Undo step. Returns `false` when the mark is the same as before.
    @discardableResult
    private func replace(_ placed: PlacedMark, with mark: Mark) -> Bool {
        guard placed.mark != mark else { return false }
        setMark(mark, of: placed)
        push(.change(placed, to: mark))
        redoSteps = []
        return true
    }

    /// A delete of one mark as one Undo step.
    private func remove(_ placed: PlacedMark) {
        guard let index = marksByDisplay[placed.displayID]?.firstIndex(where: { $0.id == placed.id }) else { return }
        marksByDisplay[placed.displayID]?.remove(at: index)
        push(.remove(placed, index: index))
        redoSteps = []
    }

    private func setMark(_ mark: Mark, of placed: PlacedMark) {
        guard let index = marksByDisplay[placed.displayID]?.firstIndex(where: { $0.id == placed.id }) else { return }
        marksByDisplay[placed.displayID]?[index].mark = mark
    }

    // MARK: Text

    /// The text field tells what the user typed.
    func textChanged(_ text: String) {
        textEdit?.text = text
    }

    /// Enter, or a click in a different place: the open text becomes a mark. An empty text adds
    /// no mark. For a text that was open again, the mark changes, and an empty text removes it.
    func completeText() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let isEmpty = edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if edit.markID != nil {
            if let placed = placed(edit.markID) {
                if isEmpty {
                    remove(placed)
                } else {
                    var mark = placed.mark
                    mark.text = edit.text
                    mark.style = edit.style
                    replace(placed, with: mark)
                }
            }
            // The mark shows again, or it is gone.
            marksChanged()
            return
        }
        guard !isEmpty else {
            onChange?()
            return
        }
        // The end of a text counts as drawing activity, so the clock of a Hold text starts here.
        lastActivity = now()
        let mark = Mark(tool: .text, style: edit.style, points: [edit.origin], text: edit.text, wrapWidth: edit.wrapWidth)
        add(mark, on: edit.displayID, stay: stay)
        marksChanged()
    }

    private func beginText(at point: CGPoint, on display: DrawDisplay) {
        // The click is the middle of the first line. Near the right or the bottom edge, the text
        // moves into the screen, so the field does not leave the screen.
        let lineHeight = (nextStyle.fontSize * 1.25).rounded(.up)
        let x = max(min(point.x, display.size.width - 2 * nextStyle.fontSize), 0).rounded()
        let y = max(min(point.y - lineHeight / 2, display.size.height - lineHeight), 0).rounded()
        textEdit = TextEdit(
            displayID: display.id, origin: CGPoint(x: x, y: y), wrapWidth: display.size.width - x, style: nextStyle, text: ""
        )
        onChange?()
    }

    // MARK: The clocks

    /// The timer calls this while `hasTimedMarks` is true. It removes the Fade and Hold marks
    /// that are fully faded. A removed mark does not come back with Undo or Redo.
    func tick() {
        guard hasTimedMarks else { return }
        if dropMarks(where: { opacity(of: $0) <= 0 }) {
            marksChanged()
        }
    }

    // MARK: Changes

    /// A hotkey, a button or a key arrives during a drag or while a text is open: the mark in
    /// progress is finished first.
    private func finishInProgress() {
        finishDrag()
        completeText()
    }

    private func finishDrag() {
        guard let drag = drag else { return }
        self.drag = nil
        let mark = draft
        draft = nil
        switch drag.kind {
        case .draw(let stay):
            lastActivity = now()
            draftRevision += 1
            if let mark = mark.map({ shaped($0, on: drag.display) }), DrawSession.isLargeEnough(mark) {
                add(mark, on: drag.display.id, stay: stay)
                marksChanged()
            } else {
                onChange?()
            }
        case .move(let placed), .resize(let placed, _, _):
            // A click with no move made no draft: nothing changed.
            guard let mark = mark else { return }
            draftRevision += 1
            replace(placed, with: mark)
            marksChanged()
        }
    }

    /// The new mark of a drag as it shows, from the draft, which has each point of the pointer.
    /// The mark stays on its screen.
    ///
    /// With Shift, a Pen or Highlight mark is one straight line from the start to the pointer
    /// (row 2.53), the angle of a Line or an Arrow goes in steps of 45 degrees (row 2.54), and a
    /// Rectangle or an Ellipse is a square or a circle (row 2.55). The draft does not change, so
    /// the mark changes back when Shift is released (row 2.56).
    private func shaped(_ draft: Mark, on display: DrawDisplay) -> Mark {
        guard draft.points.count > 1, let start = draft.points.first, let pointer = draft.points.last else { return draft }
        var mark = draft
        switch draft.tool {
        case .pen, .highlight:
            if isShiftDown { mark.points = [start, pointer] }
        case .line, .arrow, .rectangle, .ellipse:
            let end = isShiftDown
                ? DrawSession.straightEnd(of: draft, from: start, to: pointer, on: display)
                : draft.style.pointOnScreen(pointer, for: draft.tool, in: display.size)
            mark.points = [start, end]
        case .select, .text, .stamp:
            break
        }
        return mark
    }

    /// The end of a Line, an Arrow, a Rectangle or an Ellipse that Shift makes straight.
    private static func straightEnd(of mark: Mark, from start: CGPoint, to pointer: CGPoint, on display: DrawDisplay) -> CGPoint {
        let dx = pointer.x - start.x, dy = pointer.y - start.y
        // The room from the start to the edges of the screen, in the direction of the pointer.
        let inset = mark.style.edgeInset(for: mark.tool)
        let roomX = max(dx < 0 ? start.x - inset : display.size.width - inset - start.x, 0)
        let roomY = max(dy < 0 ? start.y - inset : display.size.height - inset - start.y, 0)
        if mark.tool == .rectangle || mark.tool == .ellipse {
            // The longer side of the drag is the side of the square. At an edge of the screen the
            // square stops, and it stays a square.
            let side = min(max(abs(dx), abs(dy)), roomX, roomY)
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        // The eight directions, clockwise from "to the right". The screen has y going down.
        let diagonal = CGFloat(0.5).squareRoot()
        let directions: [(x: CGFloat, y: CGFloat)] = [
            (1, 0), (diagonal, diagonal), (0, 1), (-diagonal, diagonal),
            (-1, 0), (-diagonal, -diagonal), (0, -1), (diagonal, -diagonal),
        ]
        let direction = directions[(Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8]
        // The line keeps the length of the drag. At an edge of the screen it gets shorter, and its angle stays.
        var length = hypot(dx, dy)
        if direction.x != 0 { length = min(length, roomX / abs(direction.x)) }
        if direction.y != 0 { length = min(length, roomY / abs(direction.y)) }
        return CGPoint(x: start.x + direction.x * length, y: start.y + direction.y * length)
    }

    /// The number of the next stamp: the highest number of the stamps that exist on all screens,
    /// plus 1. With no stamp, it is 1. Nothing is stored (row 2.58).
    private var nextStampNumber: Int {
        let numbers = marksByDisplay.values.joined().filter { $0.mark.tool == .stamp }.map { $0.mark.number }
        return (numbers.max() ?? 0) + 1
    }

    /// A new finished mark. Redo can no longer bring back the steps that Undo took back.
    private func add(_ mark: Mark, on displayID: CGDirectDisplayID, stay: StayMode) {
        let placed = PlacedMark(
            id: nextID, displayID: displayID, mark: mark, stay: stay,
            fadeTime: TimeInterval(prefs.fadeSeconds), shownAt: now()
        )
        nextID += 1
        marksByDisplay[displayID, default: []].append(placed)
        push(.add(placed))
        redoSteps = []
    }

    private func push(_ step: Step) {
        undoSteps.append(step)
        // The oldest step drops first. Its mark stays on the screen.
        if undoSteps.count > DrawSession.historyLimit {
            undoSteps.removeFirst(undoSteps.count - DrawSession.historyLimit)
        }
    }

    /// Removes all marks as one step. Returns `false` when no mark exists: then there is no step.
    @discardableResult
    private func clearMarks() -> Bool {
        let all = marksByDisplay.values.flatMap { $0 }
        guard !all.isEmpty else { return false }
        marksByDisplay = [:]
        push(.clear(all))
        marksChanged()
        return true
    }

    /// Undo or Redo brings marks back: the clock of a Fade or Hold mark starts again now.
    private func bringBack(_ marks: [PlacedMark]) -> [PlacedMark] {
        let time = now()
        if marks.contains(where: { $0.stay == .hold }) { lastActivity = time }
        return marks.map { mark in
            var mark = mark
            mark.shownAt = time
            return mark
        }
    }

    /// Removes the marks that match from the screens, and the steps of those marks from the
    /// history. Such a mark does not come back. Returns `true` when a mark was removed.
    @discardableResult
    private func dropMarks(where isDropped: (PlacedMark) -> Bool) -> Bool {
        var dropped = Set<Int>()
        for (displayID, marks) in marksByDisplay {
            let kept = marks.filter { !isDropped($0) }
            guard kept.count != marks.count else { continue }
            dropped.formUnion(marks.filter(isDropped).map { $0.id })
            marksByDisplay[displayID] = kept
        }
        guard !dropped.isEmpty else { return false }
        func isOfDroppedMark(_ step: Step) -> Bool {
            step.markID.map(dropped.contains) ?? false
        }
        undoSteps.removeAll(where: isOfDroppedMark)
        redoSteps.removeAll(where: isOfDroppedMark)
        return true
    }

    /// A screen is gone: its marks are dropped from the screens and from the history.
    private func dropMarksOfMissingDisplays() {
        let ids = Set(displays.map { $0.id })
        marksByDisplay = marksByDisplay.filter { ids.contains($0.key) }
        func kept(_ step: Step) -> Step? {
            switch step {
            case .add(let mark), .change(let mark, _), .remove(let mark, _):
                return ids.contains(mark.displayID) ? step : nil
            case .clear(let marks):
                let rest = marks.filter { ids.contains($0.displayID) }
                return rest.isEmpty ? nil : .clear(rest)
            }
        }
        undoSteps = undoSteps.compactMap(kept)
        redoSteps = redoSteps.compactMap(kept)
    }

    private func marksChanged() {
        marksRevision += 1
        hasTimedMarks = marksByDisplay.values.contains { $0.contains { $0.stay != .sticky } }
        if selectedID != nil, selected == nil {
            // The selected mark is gone: its clock, Undo or a clear removed it. The selection,
            // its drag and its open text go away with it (row 2.90).
            selectedID = nil
            if textEdit?.markID != nil { textEdit = nil }
            switch drag?.kind {
            case .move?, .resize?:
                drag = nil
                draft = nil
            default:
                break
            }
        }
        onChange?()
    }

    private func draftChanged() {
        draftRevision += 1
        onChange?()
    }

    /// A Pen click with no move is a dot. A Highlight line has flat ends, so it needs two points.
    /// A small Rectangle, Ellipse, Line or Arrow is a slip of the hand, and makes no mark.
    private static func isLargeEnough(_ mark: Mark) -> Bool {
        guard let first = mark.points.first, let last = mark.points.last else { return false }
        let width = abs(last.x - first.x), height = abs(last.y - first.y)
        switch mark.tool {
        case .pen: return true
        case .highlight: return mark.points.count > 1
        case .line, .arrow: return hypot(width, height) >= minimumShape
        case .rectangle, .ellipse: return max(width, height) >= minimumShape
        case .select, .text, .stamp: return false
        }
    }
}
