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
    let mark: Mark
    /// The value of the switch when the mark was drawn. A later change of the switch does not change it.
    let stay: StayMode
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
}

/// The pointer shape of the overlay.
enum PointerShape {
    /// A drag draws a mark.
    case crosshair
    /// A click puts a text.
    case iBeam
}

/// The state of the drawing part, with no window and no view (D4, D5, D6).
///
/// It holds the mode, the marks of each screen, the tool, the size, the colour, the stay mode,
/// the Undo and Redo history, and the clocks of Fade and Hold. One instance serves all screens.
/// The views are thin adapters: they turn `NSEvent`s into these calls and show what they read here.
/// Every point is in the points of its screen, with the origin at the top-left of that screen.
/// The time comes from `now`, so a test sets the clock and never sleeps.
final class DrawSession {
    /// A Fade mark is gone this long after it is finished.
    static let fadeTime: TimeInterval = 2
    /// The Hold marks stay at full strength this long after the last drawing activity.
    static let holdTime: TimeInterval = 5
    /// A mark that goes away takes this long to fade.
    static let fadeOutTime: TimeInterval = 1
    /// The number of steps that Undo can take back.
    static let historyLimit = 200
    /// A Rectangle, an Ellipse or an Arrow smaller than this makes no mark.
    static let minimumShape: CGFloat = 4

    private(set) var mode = DrawMode.off
    /// The screens that have an overlay. Empty while the mode is off.
    private(set) var displays: [DrawDisplay] = []
    private(set) var tool: Tool
    /// The size and the colour of the next mark. One value for all tools and all screens.
    private(set) var style: MarkStyle
    /// The stay mode of the next mark.
    private(set) var stay: StayMode
    /// The text that is open, if the user types one now.
    private(set) var textEdit: TextEdit?
    /// Goes up each time the finished marks change. A view makes its mark layers again only then.
    private(set) var marksRevision = 0
    /// Goes up each time the mark of the drag in progress changes.
    private(set) var draftRevision = 0
    /// True while a Fade or Hold mark exists. Only then a timer must call `tick()`.
    private(set) var hasTimedMarks = false

    /// Called after something that the views show changed.
    var onChange: (() -> Void)?

    /// One step of the history.
    private enum Step {
        case add(PlacedMark)
        /// Clear all, or the clear of Esc: all marks of all screens in one step.
        case clear([PlacedMark])
    }

    private let prefs: DrawPrefs
    private let now: () -> TimeInterval
    private var marksByDisplay: [CGDirectDisplayID: [PlacedMark]] = [:]
    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    /// The drag that draws now: its screen, and the stay mode at the pointer down.
    private var drag: (display: DrawDisplay, stay: StayMode)?
    /// The mark of the drag that draws now.
    private var draft: Mark?
    /// The last pointer down, drag or pointer up of a mark. The clock of the Hold marks starts here.
    private var lastActivity: TimeInterval = 0
    private var nextID = 1

    init(prefs: DrawPrefs, now: @escaping () -> TimeInterval) {
        self.prefs = prefs
        self.now = now
        tool = prefs.tool
        style = MarkStyle(color: prefs.color, size: prefs.size)
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

    /// The mark of the drag in progress, if it is on the given screen.
    func draft(on displayID: CGDirectDisplayID) -> Mark? {
        drag?.display.id == displayID ? draft : nil
    }

    var canUndo: Bool {
        !undoSteps.isEmpty || draft != nil || textEdit != nil
    }

    var canRedo: Bool {
        !redoSteps.isEmpty
    }

    var pointerShape: PointerShape {
        tool == .text ? .iBeam : .crosshair
    }

    /// How strong a mark shows now: 1 is full strength, 0 is gone.
    func opacity(of mark: PlacedMark) -> CGFloat {
        switch mark.stay {
        case .sticky:
            return 1
        case .fade:
            return DrawSession.strength(after: now() - mark.shownAt, fullFor: DrawSession.fadeTime - DrawSession.fadeOutTime)
        case .hold:
            return DrawSession.strength(after: now() - lastActivity, fullFor: DrawSession.holdTime)
        }
    }

    private static func strength(after elapsed: TimeInterval, fullFor full: TimeInterval) -> CGFloat {
        CGFloat(min(max(1 - (elapsed - full) / fadeOutTime, 0), 1))
    }

    // MARK: The modes

    /// The draw hotkey when the mode is off. The Sticky marks that the session kept show again.
    func start(displays newDisplays: [DrawDisplay]) {
        guard mode == .off else { return }
        mode = .drawing
        displays = newDisplays
        dropMarksOfMissingDisplays()
        marksChanged()
    }

    /// The draw hotkey when drawing is on, and the Close button. The Sticky marks stay in
    /// memory. The Fade and Hold marks are dropped.
    func stop() {
        guard mode != .off else { return }
        finishInProgress()
        dropMarks { $0.stay != .sticky }
        mode = .off
        displays = []
        marksChanged()
    }

    /// The click-through hotkey. It does nothing when the mode is off.
    func toggleClickThrough() {
        guard mode != .off else { return }
        finishInProgress()
        mode = mode == .drawing ? .clickThrough : .drawing
        onChange?()
    }

    /// Esc. It arrives only in mode drawing, because only then the overlay has the keyboard.
    func escape() {
        guard mode == .drawing else { return }
        // Esc removes the text that is not finished, and drawing stays on.
        if textEdit != nil {
            textEdit = nil
            onChange?()
            return
        }
        finishDrag()
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
        lastActivity = now()
        if tool == .text {
            beginText(at: point, on: display)
        } else {
            drag = (display, stay)
            draft = Mark(tool: tool, style: style, points: [DrawSession.clamp(point, to: display, tool: tool, style: style)])
            draftChanged()
        }
    }

    func pointerDragged(to point: CGPoint) {
        guard let drag = drag, let mark = draft else { return }
        lastActivity = now()
        // The mark stays on the screen of the pointer down, also when the pointer leaves that screen.
        let next = DrawSession.clamp(point, to: drag.display, tool: mark.tool, style: mark.style)
        switch mark.tool {
        case .pen, .highlight:
            guard mark.points.last != next else { return }
            draft?.points.append(next)
        default:
            guard mark.points.count < 2 || mark.points[1] != next else { return }
            draft?.points = [mark.points[0], next]
        }
        draftChanged()
    }

    func pointerUp(at point: CGPoint) {
        pointerDragged(to: point)
        finishDrag()
    }

    // MARK: The toolbar and the keys

    /// A click on a tool. In click-through it also goes back to mode drawing.
    func selectTool(_ newTool: Tool) {
        finishInProgress()
        tool = newTool
        prefs.tool = newTool
        if mode == .clickThrough { mode = .drawing }
        onChange?()
    }

    /// The colour of the next mark. A mark that exists does not change.
    func setColor(_ color: MarkColor) {
        style.color = color
        prefs.color = color
        // A text that is open is not a mark yet, so it gets the new colour.
        textEdit?.style = style
        onChange?()
    }

    func setSize(_ size: MarkSize) {
        style.size = size
        prefs.size = size
        textEdit?.style = style
        onChange?()
    }

    /// The switch Fade, Hold, Sticky. A mark that exists keeps its value.
    func setStay(_ newStay: StayMode) {
        stay = newStay
        prefs.stay = newStay
        onChange?()
    }

    /// Takes back the newest step. A text that is open is finished first, and then it is the newest mark.
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
            marksChanged()
        case .clear:
            clearMarks()
        }
    }

    /// The Clear all button and the menu row: each mark on each screen goes away. One Undo brings them back.
    func clearAll() {
        finishInProgress()
        if clearMarks() { redoSteps = [] }
    }

    // MARK: Text

    /// The text field tells what the user typed.
    func textChanged(_ text: String) {
        textEdit?.text = text
    }

    /// Enter, or a click in a different place: the open text becomes a mark. An empty text adds no mark.
    func completeText() {
        guard let edit = textEdit else { return }
        textEdit = nil
        guard !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        let lineHeight = (style.fontSize * 1.25).rounded(.up)
        let x = max(min(point.x, display.size.width - 2 * style.fontSize), 0).rounded()
        let y = max(min(point.y - lineHeight / 2, display.size.height - lineHeight), 0).rounded()
        textEdit = TextEdit(
            displayID: display.id, origin: CGPoint(x: x, y: y), wrapWidth: display.size.width - x, style: style, text: ""
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
        lastActivity = now()
        guard let mark = draft else { return }
        draft = nil
        draftRevision += 1
        if DrawSession.isLargeEnough(mark) {
            add(mark, on: drag.display.id, stay: drag.stay)
            marksChanged()
        } else {
            onChange?()
        }
    }

    /// A new finished mark. Redo can no longer bring back the steps that Undo took back.
    private func add(_ mark: Mark, on displayID: CGDirectDisplayID, stay: StayMode) {
        let placed = PlacedMark(id: nextID, displayID: displayID, mark: mark, stay: stay, shownAt: now())
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

    /// Removes the marks that match from the screens, and the steps that added them from the
    /// Undo list. Such a mark does not come back. Returns `true` when a mark was removed.
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
        undoSteps.removeAll { step in
            if case .add(let mark) = step { return dropped.contains(mark.id) }
            return false
        }
        return true
    }

    /// A screen is gone: its marks are dropped from the screens and from the history.
    private func dropMarksOfMissingDisplays() {
        let ids = Set(displays.map { $0.id })
        marksByDisplay = marksByDisplay.filter { ids.contains($0.key) }
        func kept(_ step: Step) -> Step? {
            switch step {
            case .add(let mark):
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
        onChange?()
    }

    private func draftChanged() {
        draftRevision += 1
        onChange?()
    }

    /// A Pen click with no move is a dot. A Highlight line has flat ends, so it needs two points.
    /// A small Rectangle, Ellipse or Arrow is a slip of the hand, and makes no mark.
    private static func isLargeEnough(_ mark: Mark) -> Bool {
        guard let first = mark.points.first, let last = mark.points.last else { return false }
        let width = abs(last.x - first.x), height = abs(last.y - first.y)
        switch mark.tool {
        case .pen: return true
        case .highlight: return mark.points.count > 1
        case .arrow: return hypot(width, height) >= minimumShape
        case .rectangle, .ellipse: return max(width, height) >= minimumShape
        case .text: return false
        }
    }

    /// The point of a drag, kept on its screen: half a line width before the edge, so the full
    /// line is visible.
    private static func clamp(_ point: CGPoint, to display: DrawDisplay, tool: Tool, style: MarkStyle) -> CGPoint {
        let inset = style.lineWidth(for: tool) / 2
        func clamp(_ value: CGFloat, length: CGFloat) -> CGFloat {
            // A screen that is narrower than the line keeps the point in its middle.
            let low = min(inset, length / 2)
            return min(max(value, low), length - low)
        }
        return CGPoint(x: clamp(point.x, length: display.size.width), y: clamp(point.y, length: display.size.height))
    }
}
