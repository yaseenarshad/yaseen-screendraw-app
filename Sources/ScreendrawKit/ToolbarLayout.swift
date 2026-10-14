import CoreGraphics

/// The four forms of the toolbar (D16). The toolbar is one row. At the left or the right edge of
/// a screen it is one column. A screen that is too small for the row or the column gets two.
enum ToolbarForm: String, CaseIterable {
    case row, twoRows, column, twoColumns

    var isVertical: Bool { self == .column || self == .twoColumns }
    var lineCount: Int { self == .row || self == .column ? 1 : 2 }

    /// One row or one column when it fits in the visible part of the screen, else two (rows 2.101, 2.103).
    static func fitting(vertical: Bool, in visible: CGRect, size: (ToolbarForm) -> CGSize) -> ToolbarForm {
        if vertical { return size(.column).height <= visible.height ? .column : .twoColumns }
        return size(.row).width <= visible.width ? .row : .twoRows
    }
}

/// Where the grip and each button of the toolbar are, for one form.
///
/// No view here. The sizes of the buttons come in as groups, and the frames go out. Thus a new
/// tool needs no change of the layout, and a test gives any number of buttons.
/// The origin is at the top-left, as in the toolbar view.
struct ToolbarLayout: Equatable {
    /// The room between the edge of the toolbar and its content.
    static let padding: CGFloat = 4
    /// The room between two buttons of a group.
    static let spacing: CGFloat = 2
    /// The room between two groups. A drag that starts there moves the toolbar.
    static let groupGap: CGFloat = 9
    /// The room between the two rows or the two columns.
    static let lineGap: CGFloat = 8
    /// The length of the grip, in the direction of the toolbar.
    static let gripLength: CGFloat = 10

    let size: CGSize
    /// The grip is at the start of the toolbar: at the left of the rows, or at the top of the columns.
    let grip: CGRect
    /// The frame of each button, in the groups and in the order of `groups`.
    let frames: [[CGRect]]

    init(form: ToolbarForm, groups: [[CGSize]]) {
        let isVertical = form.isVertical
        // "Along" is the direction of a line of buttons. "Across" is the other direction.
        func along(_ size: CGSize) -> CGFloat { isVertical ? size.height : size.width }
        func across(_ size: CGSize) -> CGFloat { isVertical ? size.width : size.height }
        func length(_ line: ArraySlice<[CGSize]>) -> CGFloat {
            let gaps = line.map { CGFloat(max($0.count - 1, 0)) * ToolbarLayout.spacing }.reduce(0, +)
            return line.joined().map(along).reduce(0, +) + gaps + CGFloat(max(line.count - 1, 0)) * ToolbarLayout.groupGap
        }

        // Two lines: the groups keep their order, and the longer line is as short as possible.
        var lines = [groups[...]]
        if form.lineCount == 2, groups.count > 1 {
            func longer(_ split: Int) -> CGFloat { max(length(groups[..<split]), length(groups[split...])) }
            let split = (1..<groups.count).min { longer($0) < longer($1) } ?? 1
            lines = [groups[..<split], groups[split...]]
        }

        let start = ToolbarLayout.padding + ToolbarLayout.gripLength + ToolbarLayout.groupGap
        var frames: [[CGRect]] = []
        var lineStart = ToolbarLayout.padding
        for line in lines {
            // A line is as thick as its largest button. A smaller button is in the middle of the line.
            let thickness = line.joined().map(across).max() ?? 0
            var position = start
            for (index, group) in line.enumerated() {
                if index > 0 { position += ToolbarLayout.groupGap }
                var groupFrames: [CGRect] = []
                for (buttonIndex, button) in group.enumerated() {
                    if buttonIndex > 0 { position += ToolbarLayout.spacing }
                    let offset = lineStart + ((thickness - across(button)) / 2).rounded(.down)
                    groupFrames.append(CGRect(
                        origin: isVertical ? CGPoint(x: offset, y: position) : CGPoint(x: position, y: offset), size: button
                    ))
                    position += along(button)
                }
                frames.append(groupFrames)
            }
            lineStart += thickness + ToolbarLayout.lineGap
        }
        self.frames = frames

        let length = start + (lines.map(length).max() ?? 0) + ToolbarLayout.padding
        let thickness = lineStart - ToolbarLayout.lineGap + ToolbarLayout.padding
        let gripAcross = thickness - 2 * ToolbarLayout.padding
        let corner = CGPoint(x: ToolbarLayout.padding, y: ToolbarLayout.padding)
        if isVertical {
            size = CGSize(width: thickness, height: length)
            grip = CGRect(origin: corner, size: CGSize(width: gripAcross, height: ToolbarLayout.gripLength))
        } else {
            size = CGSize(width: length, height: thickness)
            grip = CGRect(origin: corner, size: CGSize(width: ToolbarLayout.gripLength, height: gripAcross))
        }
    }
}

// MARK: Where the toolbar goes

// The pure rules of the place (rows 2.102 to 2.105, 2.112). Each frame is in the global points of
// AppKit: the origin is at the bottom-left. `visible` is a screen with no menu bar and no Dock.
extension ToolbarLayout {
    /// A drop this near to the left or the right edge of a screen makes a column (row 2.102).
    static let nearEdge: CGFloat = 120
    /// The room between a column and its edge of the screen.
    static let edgeMargin: CGFloat = 8
    /// The room between the toolbar and its tip.
    static let tipGap: CGFloat = 6

    /// The form and the frame of the toolbar after the user released it.
    ///
    /// Near the left or the right edge it is a column at that edge. At each other place it is a
    /// row. "Near" is: the middle of the toolbar, or the pointer, is less than `nearEdge` from the
    /// edge, or past it. The pointer counts too, because the grip is at the start of the toolbar:
    /// with the grip at the left edge of a screen, the middle of a row is far from that edge.
    ///
    /// - Parameters:
    ///   - frame: where the user released the toolbar.
    ///   - pointer: where the pointer is at the release.
    ///   - visible: the visible part of the screen of the drop.
    ///   - size: the size of the toolbar in a form.
    static func drop(
        _ frame: CGRect, pointer: CGPoint, on visible: CGRect, size: (ToolbarForm) -> CGSize
    ) -> (form: ToolbarForm, frame: CGRect) {
        let isNearLeft = min(frame.midX, pointer.x) < visible.minX + nearEdge
        let isNearRight = max(frame.midX, pointer.x) > visible.maxX - nearEdge
        let form = ToolbarForm.fitting(vertical: isNearLeft || isNearRight, in: visible, size: size)
        let newSize = size(form)
        // The grip stays where the user released it: the top-left corner does not move.
        var x = frame.minX
        if isNearLeft {
            x = visible.minX + edgeMargin
        } else if isNearRight {
            x = visible.maxX - edgeMargin - newSize.width
        }
        let dropped = CGRect(x: x.rounded(), y: (frame.maxY - newSize.height).rounded(), width: newSize.width, height: newSize.height)
        return (form, keep(dropped, inside: visible))
    }

    /// Moves a frame fully into the visible part of a screen (row 2.105). A frame that is too
    /// large keeps its top-left corner there, where the grip is.
    static func keep(_ frame: CGRect, inside visible: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = min(visible.maxY - frame.height, max(frame.minY, visible.minY))
        return frame
    }

    /// Where the tip of a button shows: at the side of the toolbar that has room (row 2.112).
    /// A row has its tip above it, or below it at the top of the screen. A column has its tip
    /// at its right, or at its left at the right edge of the screen.
    static func tipOrigin(size: CGSize, button: CGRect, toolbar: CGRect, isVertical: Bool, on visible: CGRect) -> CGPoint {
        var tip = CGRect(origin: .zero, size: size)
        if isVertical {
            let right = toolbar.maxX + tipGap
            tip.origin.x = right + size.width <= visible.maxX ? right : toolbar.minX - tipGap - size.width
            tip.origin.y = (button.midY - size.height / 2).rounded()
            tip.origin.y = keep(tip, inside: visible).minY
        } else {
            let above = toolbar.maxY + tipGap
            tip.origin.y = above + size.height <= visible.maxY ? above : toolbar.minY - tipGap - size.height
            tip.origin.x = (button.midX - size.width / 2).rounded()
            tip.origin.x = keep(tip, inside: visible).minX
        }
        return tip.origin
    }
}
