import CoreGraphics

// The geometry of a mark for the Select tool (D14): the hit test, the bounds, the handles, a move
// and a size change. Pure functions, with no view. `DrawSession` holds the selection.

/// One of the eight handles of a selected Rectangle or Ellipse.
enum Handle: Hashable, CaseIterable {
    // The corners come first: a corner wins when two hit areas are equally near.
    case topLeft, topRight, bottomRight, bottomLeft
    case top, right, bottom, left

    /// The edge that this handle moves on the x axis: -1 the left edge, 1 the right edge, 0 none.
    var horizontal: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: return -1
        case .topRight, .right, .bottomRight: return 1
        case .top, .bottom: return 0
        }
    }

    /// The edge that this handle moves on the y axis: -1 the top edge, 1 the bottom edge, 0 none.
    var vertical: Int {
        switch self {
        case .topLeft, .top, .topRight: return -1
        case .bottomLeft, .bottom, .bottomRight: return 1
        case .left, .right: return 0
        }
    }

    /// The place of the handle: a corner of `rect`, or the middle of an edge.
    func point(of rect: CGRect) -> CGPoint {
        CGPoint(
            x: horizontal < 0 ? rect.minX : horizontal > 0 ? rect.maxX : rect.midX,
            y: vertical < 0 ? rect.minY : vertical > 0 ? rect.maxY : rect.midY
        )
    }
}

/// A handle of the selected mark.
enum MarkHandle: Hashable {
    /// Rectangle and Ellipse: one of the eight handles of the rectangle of the mark.
    case frame(Handle)
    /// Line and Arrow: the start (0) or the end (1).
    case end(Int)
}

/// The head of an Arrow: a triangle with its tip at the end of the drag.
struct ArrowHead {
    let tip: CGPoint
    /// The middle of the side that is opposite the tip. The line of the Arrow stops here.
    let base: CGPoint
    /// From the start of the Arrow to its tip, with a length of 1.
    let direction: CGPoint
    /// Half the length of the side that is opposite the tip.
    let halfWidth: CGFloat
    /// False for a short Arrow, which is only a head.
    let hasShaft: Bool

    var left: CGPoint { beside(base, -halfWidth) }
    var right: CGPoint { beside(base, halfWidth) }

    /// The point that is `distance` to the side of `point`, across the Arrow.
    func beside(_ point: CGPoint, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x - direction.y * distance, y: point.y + direction.x * distance)
    }
}

/// The part of a mark that is below a point.
enum MarkPart: Equatable {
    /// The line of the mark, its text, or its circle.
    case line
    /// The empty inside of a Rectangle or an Ellipse.
    case inside
}

extension Mark {
    /// A click this near to the line of a mark selects the mark.
    static let hitTolerance: CGFloat = 6
    /// The space between a mark and the outline that shows when it is selected.
    static let outlineGap: CGFloat = 3
    /// The side of the square around a handle that takes a pointer down. The visible handle is smaller.
    static let handleHitSide: CGFloat = 12
    /// The smallest side of a Rectangle or an Ellipse, and the smallest length of a Line or an Arrow.
    static let minimumSide: CGFloat = 4

    var lineWidth: CGFloat { style.lineWidth(for: tool) }

    /// The smallest rectangle around the points. For a Rectangle and an Ellipse, the middle of
    /// the line is on its edge.
    var frame: CGRect {
        guard let first = points.first else { return .null }
        var low = first, high = first
        for point in points.dropFirst() {
            low = CGPoint(x: min(low.x, point.x), y: min(low.y, point.y))
            high = CGPoint(x: max(high.x, point.x), y: max(high.y, point.y))
        }
        return CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
    }

    /// The area that the mark covers, with the width of its line.
    var bounds: CGRect {
        let line = frame.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        switch tool {
        case .rectangle, .ellipse, .pen, .highlight, .line:
            return line
        case .arrow:
            // The head is wider than the line.
            guard let head = arrowHead else { return line }
            let minX = min(line.minX, head.left.x, head.right.x), maxX = max(line.maxX, head.left.x, head.right.x)
            let minY = min(line.minY, head.left.y, head.right.y), maxY = max(line.maxY, head.left.y, head.right.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            guard let origin = points.first else { return .null }
            return TextLayout(text: text, style: style, wrapWidth: wrapWidth).usedRect
                .offsetBy(dx: origin.x, dy: origin.y)
        case .stamp:
            return frame.insetBy(dx: -style.stampDiameter / 2, dy: -style.stampDiameter / 2)
        case .select:
            return .null
        }
    }

    /// The outline that the overlay shows around the selected mark.
    var outline: CGRect {
        bounds.insetBy(dx: -Mark.outlineGap, dy: -Mark.outlineGap)
    }

    /// The head of an Arrow. `nil` for an Arrow with no length. `MarkRenderer` draws the head
    /// from these numbers, so the hit test and the picture agree.
    var arrowHead: ArrowHead? {
        guard tool == .arrow, let start = points.first, let end = points.last else { return nil }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return nil }
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        // The head grows with the line width. A short arrow is only a head.
        let headLength = min(lineWidth * 3 + 6, length)
        return ArrowHead(
            tip: end,
            base: CGPoint(x: end.x - direction.x * headLength, y: end.y - direction.y * headLength),
            direction: direction,
            halfWidth: headLength * 0.45,
            hasShaft: length > headLength
        )
    }

    // MARK: The hit test

    /// The part of the mark at `point`, or `nil` when the point is more than `tolerance` away
    /// from the mark. The empty inside of a Rectangle and of an Ellipse is a part too, so a
    /// click inside selects the mark.
    func part(at point: CGPoint, tolerance: CGFloat = Mark.hitTolerance) -> MarkPart? {
        let reach = lineWidth / 2 + tolerance
        let frame = self.frame
        switch tool {
        case .rectangle:
            // How far the point is outside the rectangle of the line (below zero: inside).
            let outside = max(abs(point.x - frame.midX) - frame.width / 2, abs(point.y - frame.midY) - frame.height / 2)
            if outside > reach { return nil }
            return outside < -reach ? .inside : .line
        case .ellipse:
            /// True when the point is in the ellipse that is `extra` larger on each side.
            func isInEllipse(_ extra: CGFloat) -> Bool {
                let a = frame.width / 2 + extra, b = frame.height / 2 + extra
                guard a > 0, b > 0 else { return false }
                let x = (point.x - frame.midX) / a, y = (point.y - frame.midY) / b
                return x * x + y * y <= 1
            }
            guard isInEllipse(reach) else { return nil }
            return isInEllipse(-reach) ? .inside : .line
        case .arrow:
            if Mark.distance(from: point, toLineThrough: points) <= reach { return .line }
            guard let head = arrowHead else { return nil }
            return Mark.triangle(head.tip, head.left, head.right, contains: point) ? .line : nil
        case .pen, .highlight, .line:
            return Mark.distance(from: point, toLineThrough: points) <= reach ? .line : nil
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ? .line : nil
        case .stamp:
            return Mark.distance(from: point, toLineThrough: points) <= style.stampDiameter / 2 + tolerance ? .line : nil
        case .select:
            return nil
        }
    }

    /// The distance from `point` to the nearest point of the line through `points`.
    private static func distance(from point: CGPoint, toLineThrough points: [CGPoint]) -> CGFloat {
        guard var a = points.first else { return .infinity }
        var nearest = hypot(point.x - a.x, point.y - a.y)
        for b in points.dropFirst() {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            // How far along the segment from a to b the nearest point is, from 0 to 1.
            let along = lengthSquared > 0
                ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
                : 0
            nearest = min(nearest, hypot(point.x - a.x - along * dx, point.y - a.y - along * dy))
            a = b
        }
        return nearest
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, contains point: CGPoint) -> Bool {
        // The point is in the triangle when it is on the same side of all three edges.
        func side(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
            (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
        }
        let sides = [side(a, b), side(b, c), side(c, a)]
        return sides.allSatisfy { $0 >= 0 } || sides.allSatisfy { $0 <= 0 }
    }

    // MARK: Handles, move and size change

    /// The handles of the selected mark, with their places: eight for a Rectangle and an Ellipse,
    /// and one at each end of a Line and an Arrow. A Pen, a Highlight, a Text and a Stamp only
    /// move (row 2.83).
    var handles: [(key: MarkHandle, point: CGPoint)] {
        switch tool {
        case .rectangle, .ellipse:
            let frame = self.frame
            return Handle.allCases.map { (.frame($0), $0.point(of: frame)) }
        case .line, .arrow:
            return points.indices.map { (.end($0), points[$0]) }
        case .pen, .highlight, .text, .stamp, .select:
            return []
        }
    }

    /// The handle that a pointer down at `point` takes, with its place: the nearest handle that
    /// has the point in its hit area. The first handle wins when two are equally near.
    func handle(at point: CGPoint) -> (key: MarkHandle, point: CGPoint)? {
        let reach = Mark.handleHitSide / 2
        var nearest: (handle: (key: MarkHandle, point: CGPoint), distance: CGFloat)?
        for handle in handles {
            let distance = max(abs(point.x - handle.point.x), abs(point.y - handle.point.y))
            if distance <= reach, distance < nearest?.distance ?? .infinity {
                nearest = (handle, distance)
            }
        }
        return nearest?.handle
    }

    /// The mark moved by `delta`, on a screen of `size`. The move stops when the bounds of the
    /// mark touch an edge of the screen (row 2.82).
    func moved(by delta: CGPoint, in size: CGSize) -> Mark {
        let bounds = self.bounds
        var room = CGPoint(x: size.width - bounds.maxX, y: size.height - bounds.maxY)
        if tool == .text {
            // A text stays on whole points, as a new text. Then the width for its lines (below)
            // is never less than the lines need, and the text has the same lines at the edge.
            room = CGPoint(x: room.x.rounded(.down), y: room.y.rounded(.down))
        }
        // Whole points, so a sharp line stays sharp. A mark that is larger than the screen keeps
        // its top-left corner on the screen.
        let dx = max(min(delta.x.rounded(), room.x), -bounds.minX)
        let dy = max(min(delta.y.rounded(), room.y), -bounds.minY)
        var moved = self
        moved.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        if tool == .text, let origin = moved.points.first {
            // A line of a text always breaks at the right edge of the screen.
            moved.wrapWidth = size.width - origin.x
        }
        return moved
    }

    /// The mark after `handle` moved to `point`, on a screen of `size`. For a Rectangle and an
    /// Ellipse, the opposite edges stay, a handle that goes through the opposite edge turns the
    /// mark over, and the smallest side is `minimumSide`. An end of a Line or an Arrow moves, and
    /// its other end stays.
    func resized(_ handle: MarkHandle, to point: CGPoint, in size: CGSize) -> Mark {
        var resized = self
        switch handle {
        case .frame(let handle):
            // The middle of the line stops half a line width before each edge of the screen, as
            // in a drag that draws.
            let inset = style.pointOnScreen(.zero, for: tool, in: size)
            let frame = self.frame
            var rect = frame
            if handle.horizontal != 0 {
                let x = Mark.span(
                    fixed: handle.horizontal < 0 ? frame.maxX : frame.minX,
                    moving: point.x.rounded(), from: inset.x, to: size.width - inset.x
                )
                rect.origin.x = x.origin
                rect.size.width = x.length
            }
            if handle.vertical != 0 {
                let y = Mark.span(
                    fixed: handle.vertical < 0 ? frame.maxY : frame.minY,
                    moving: point.y.rounded(), from: inset.y, to: size.height - inset.y
                )
                rect.origin.y = y.origin
                rect.size.height = y.length
            }
            resized.points = [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)]
        case .end(let index):
            guard points.count == 2, points.indices.contains(index) else { return self }
            let fixed = points[1 - index]
            var end = style.pointOnScreen(point, for: tool, in: size)
            let length = hypot(end.x - fixed.x, end.y - fixed.y)
            guard length > 0 else { return self }
            if length < Mark.minimumSide {
                // A line with no length draws nothing. The end stays this far from the other
                // end, in the direction of the pointer.
                let scale = Mark.minimumSide / length
                let far = CGPoint(x: fixed.x + (end.x - fixed.x) * scale, y: fixed.y + (end.y - fixed.y) * scale)
                end = style.pointOnScreen(far, for: tool, in: size)
            }
            resized.points[index] = end
        }
        return resized
    }

    /// One axis of a rectangle, between an edge that stays and an edge that follows the pointer.
    /// The result is inside `low...high`, and at least `minimumSide` long.
    private static func span(
        fixed: CGFloat, moving: CGFloat, from low: CGFloat, to high: CGFloat
    ) -> (origin: CGFloat, length: CGFloat) {
        let a = min(max(fixed, low), high)
        let b = min(max(moving, low), high)
        let length = max(abs(b - a), minimumSide)
        // A short rectangle grows from the fixed edge towards the pointer. At the edge of the
        // screen it moves back in.
        let origin = b < a ? a - length : a
        return (min(max(origin, low), max(high - length, low)), length)
    }
}

/// The mark that a click at `point` selects, among the marks of one screen (the oldest first).
/// The mark that was drawn last wins. A click on a line wins over a click in the empty inside of
/// a Rectangle or an Ellipse. Thus a mark inside a larger mark can be selected.
func topMark(at point: CGPoint, in marks: [PlacedMark]) -> PlacedMark? {
    var inside: PlacedMark?
    for placed in marks.reversed() {
        switch placed.mark.part(at: point) {
        case .line?: return placed
        case .inside?: inside = inside ?? placed
        case nil: break
        }
    }
    return inside
}
