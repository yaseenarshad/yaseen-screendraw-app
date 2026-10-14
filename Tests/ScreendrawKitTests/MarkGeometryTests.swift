import AppKit
@testable import ScreendrawKit
import Testing

/// The geometry of a mark for the Select tool (D14), with no session and no view: the hit test,
/// the handles, a move and a size change. A "sister row" is a scenario row of YAZ-2782, the
/// Select tool of the sister app. The rows of YAZ-2828 that these tests prove are 2.81 to 2.83.
@MainActor @Suite struct MarkGeometryTests {
    /// The screen of these tests: 100 by 60 points.
    private let screen = CGSize(width: 100, height: 60)

    private func mark(_ tool: Tool, _ size: MarkSize, _ points: [CGPoint]) -> Mark {
        Mark(tool: tool, style: MarkStyle(color: .red, size: size), points: points)
    }

    private func text(_ string: String, at origin: CGPoint, _ size: MarkSize = .thick) -> Mark {
        Mark(tool: .text, style: MarkStyle(color: .red, size: size), points: [origin], text: string, wrapWidth: screen.width - origin.x)
    }

    private func placed(_ marks: [Mark]) -> [PlacedMark] {
        marks.enumerated().map { PlacedMark(id: $0.offset, displayID: 1, mark: $0.element, stay: .sticky, fadeTime: 2, shownAt: 0) }
    }

    private func isNear(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    /// The tolerance is 6 points around the line of a mark.
    @Test func sisterRow5_theHitTestOfEachKindOfMarkHasATolerance() {
        #expect(Mark.hitTolerance == 6)

        // Rectangle, Medium: the line is 4 points, so a click 8 points from its middle still hits.
        let rectangle = mark(.rectangle, .medium, [point(20, 20), point(80, 60)])
        #expect(rectangle.part(at: point(20, 40)) == .line)
        #expect(rectangle.part(at: point(12, 40)) == .line && rectangle.part(at: point(11, 40)) == nil)
        #expect(rectangle.part(at: point(12, 12)) == .line && rectangle.part(at: point(11, 12)) == nil)
        #expect(rectangle.part(at: point(50, 68)) == .line && rectangle.part(at: point(50, 69)) == nil)
        // With no tolerance, only the line itself hits.
        #expect(rectangle.part(at: point(18, 40), tolerance: 0) == .line)
        #expect(rectangle.part(at: point(17, 40), tolerance: 0) == nil)

        // Ellipse, Thin: 7 points from the middle of the line. It is not hit at the corner of its rectangle.
        let ellipse = mark(.ellipse, .thin, [point(80, 60), point(20, 20)])
        #expect(ellipse.part(at: point(20, 40)) == .line)
        #expect(ellipse.part(at: point(13, 40)) == .line && ellipse.part(at: point(12, 40)) == nil)
        #expect(ellipse.part(at: point(50, 67)) == .line && ellipse.part(at: point(50, 68)) == nil)
        #expect(ellipse.part(at: point(22, 22)) == nil)

        // Arrow, Thick: 9.5 points from the line, and the head, which is wider than that.
        let arrow = mark(.arrow, .thick, [point(20, 30), point(80, 30)])
        #expect(arrow.part(at: point(50, 30)) == .line)
        #expect(arrow.part(at: point(50, 39)) == .line && arrow.part(at: point(50, 40)) == nil)
        #expect(arrow.part(at: point(11, 30)) == .line && arrow.part(at: point(10, 30)) == nil)
        #expect(arrow.part(at: point(89, 30)) == .line && arrow.part(at: point(90, 30)) == nil)
        // The head is 27 points long and 12 points wide at each side of its base, at x 53.
        #expect(arrow.part(at: point(55, 41)) == .line && arrow.part(at: point(55, 19)) == .line)
        #expect(arrow.part(at: point(75, 41)) == nil)
        // The bounds have the round start of the line, the tip, and the full width of the head.
        #expect(isNear(arrow.bounds.minX, 16.5) && isNear(arrow.bounds.maxX, 83.5))
        #expect(isNear(arrow.bounds.minY, 17.85) && isNear(arrow.bounds.maxY, 42.15))

        // Line, Thick: 9.5 points from the line. It has no head.
        let line = mark(.line, .thick, [point(20, 30), point(80, 30)])
        #expect(line.part(at: point(50, 39)) == .line && line.part(at: point(50, 40)) == nil)
        #expect(line.part(at: point(89, 30)) == .line && line.part(at: point(90, 30)) == nil)
        #expect(line.part(at: point(55, 41)) == nil)
        #expect(line.bounds == CGRect(x: 16.5, y: 26.5, width: 67, height: 7))

        // Pen, Thin: 7 points from each part of the line, also around a corner.
        let pen = mark(.pen, .thin, [point(10, 10), point(40, 10), point(40, 40)])
        #expect(pen.part(at: point(25, 17)) == .line && pen.part(at: point(25, 18)) == nil)
        #expect(pen.part(at: point(47, 25)) == .line && pen.part(at: point(48, 25)) == nil)
        #expect(pen.part(at: point(44, 6)) == .line && pen.part(at: point(45, 5)) == nil)
        #expect(pen.part(at: point(25, 30)) == nil)

        // Highlight, Thick: the line is 24 points, so 18 points from its middle.
        let highlight = mark(.highlight, .thick, [point(10, 30), point(90, 30)])
        #expect(highlight.part(at: point(50, 48)) == .line && highlight.part(at: point(50, 49)) == nil)
        #expect(highlight.part(at: point(50, 12)) == .line && highlight.part(at: point(50, 11)) == nil)

        // Text: the area of its lines, and 6 points around it.
        let hello = text("Hello", at: point(10, 5))
        let bounds = hello.bounds
        #expect(bounds.minX == 10 && bounds.minY == 5)
        #expect(bounds.width > 40 && bounds.width < 80 && bounds.height > 24 && bounds.height < 36)
        #expect(hello.part(at: point(bounds.midX, bounds.midY)) == .line)
        #expect(hello.part(at: point(bounds.maxX + 5, bounds.midY)) == .line)
        #expect(hello.part(at: point(bounds.maxX + 7, bounds.midY)) == nil)
        #expect(hello.part(at: point(bounds.midX, bounds.maxY + 5)) == .line)
        #expect(hello.part(at: point(bounds.midX, bounds.maxY + 7)) == nil)

        // Stamp, Medium: a circle of 30 points, and 6 points around it. Its corner is not a hit.
        let stamp = mark(.stamp, .medium, [point(50, 30)])
        #expect(stamp.bounds == CGRect(x: 35, y: 15, width: 30, height: 30))
        #expect(stamp.part(at: point(50, 30)) == .line && stamp.part(at: point(64, 30)) == .line)
        #expect(stamp.part(at: point(71, 30)) == .line && stamp.part(at: point(72, 30)) == nil)
        #expect(stamp.part(at: point(50, 9)) == .line && stamp.part(at: point(50, 8)) == nil)
        #expect(stamp.part(at: point(66, 46)) == nil)
    }

    /// A Rectangle and an Ellipse are selected by a click on the outline, and also by a click inside.
    @Test func sisterRow6_theInsideOfARectangleAndOfAnEllipseIsAPartOfTheMark() {
        let rectangle = mark(.rectangle, .medium, [point(20, 20), point(80, 60)])
        #expect(rectangle.part(at: point(28, 40)) == .line && rectangle.part(at: point(29, 40)) == .inside)
        #expect(rectangle.part(at: point(50, 40)) == .inside)
        #expect(rectangle.part(at: point(23, 40), tolerance: 0) == .inside)

        let ellipse = mark(.ellipse, .thin, [point(80, 60), point(20, 20)])
        #expect(ellipse.part(at: point(26, 40)) == .line && ellipse.part(at: point(28, 40)) == .inside)
        #expect(ellipse.part(at: point(50, 40)) == .inside)
    }

    /// Two marks overlap at the click: the mark that was drawn last is selected. One addition of
    /// the sister app: a line wins over the empty inside of a larger mark.
    @Test func sisterRow7_theMarkThatWasDrawnLastWinsAndALineWinsOverAnEmptyInside() {
        func id(at point: CGPoint, in marks: [Mark]) -> Int? {
            topMark(at: point, in: placed(marks))?.id
        }
        var marks: [Mark] = []
        #expect(id(at: point(50, 30), in: marks) == nil)
        marks.append(mark(.pen, .thin, [point(10, 30), point(90, 30)])) // 0: a line from the left to the right
        marks.append(mark(.pen, .thin, [point(50, 10), point(50, 50)])) // 1: a line from the top to the bottom
        // The two lines cross at 50, 30: the line that was drawn last wins.
        #expect(id(at: point(50, 30), in: marks) == 1)
        #expect(id(at: point(20, 30), in: marks) == 0)
        #expect(id(at: point(50, 45), in: marks) == 1)
        #expect(id(at: point(80, 50), in: marks) == nil)

        // A large rectangle that was drawn last, around the two lines.
        marks.append(mark(.rectangle, .thin, [point(5, 5), point(95, 55)])) // 2
        // In its empty inside, away from the lines: the rectangle.
        #expect(id(at: point(75, 45), in: marks) == 2)
        // On a line inside it: the line, although the rectangle was drawn last.
        #expect(id(at: point(50, 30), in: marks) == 1)
        #expect(id(at: point(30, 33), in: marks) == 0)
        // On the line of the rectangle and on the first line: two lines, so the last one wins.
        #expect(id(at: point(8, 30), in: marks) == 2)

        // Two rectangles, the small one inside the large one. In both insides, the last one wins.
        let small = mark(.rectangle, .thin, [point(30, 20), point(60, 40)])
        let large = mark(.rectangle, .thin, [point(5, 5), point(95, 55)])
        #expect(id(at: point(45, 30), in: [small, large]) == 1)
        // The line of the small rectangle still selects it.
        #expect(id(at: point(30, 30), in: [small, large]) == 0)
        #expect(id(at: point(45, 30), in: [large, small]) == 1 && id(at: point(80, 30), in: [large, small]) == 0)
    }

    /// The handles of row 2.83: eight for a Rectangle and an Ellipse, one at each end of a Line
    /// and an Arrow, and none for a Pen, a Highlight, a Text and a Stamp.
    @Test func sisterRow10_theHandlesOfEachKindOfMark() {
        let rectangle = mark(.rectangle, .medium, [point(60, 40), point(20, 10)])
        // On the corners and the edge middles of the rectangle. The hit area is 12 by 12 points.
        #expect(rectangle.handles.map(\.key) == Handle.allCases.map { MarkHandle.frame($0) })
        #expect(rectangle.handles.map(\.point) == [
            point(20, 10), point(60, 10), point(60, 40), point(20, 40),
            point(40, 10), point(60, 25), point(40, 40), point(20, 25),
        ])
        #expect(rectangle.handle(at: point(62, 27))?.key == .frame(.right))
        #expect(rectangle.handle(at: point(66, 25))?.key == .frame(.right) && rectangle.handle(at: point(67, 25)) == nil)
        #expect(rectangle.handle(at: point(58, 43))?.key == .frame(.bottomRight))
        #expect(rectangle.handle(at: point(40, 25)) == nil)
        #expect(mark(.ellipse, .thin, [point(20, 10), point(60, 40)]).handles.count == 8)

        for tool in [Tool.arrow, .line] {
            let line = mark(tool, .medium, [point(20, 30), point(80, 30)])
            #expect(line.handles.map(\.key) == [.end(0), .end(1)], "\(tool)")
            #expect(line.handles.map(\.point) == [point(20, 30), point(80, 30)], "\(tool)")
            #expect(line.handle(at: point(83, 27))?.key == .end(1) && line.handle(at: point(50, 30)) == nil, "\(tool)")
        }

        let onlyMove = [
            mark(.pen, .thin, [point(10, 10), point(40, 40)]), mark(.highlight, .thin, [point(10, 10), point(40, 40)]),
            text("Hi", at: point(10, 10)), mark(.stamp, .thin, [point(30, 30)]),
        ]
        for mark in onlyMove {
            #expect(mark.handles.isEmpty && mark.handle(at: mark.points[0]) == nil, "\(mark.tool)")
        }
    }

    /// Row 2.82: the move stops when the bounds of the mark touch an edge of the screen.
    @Test func sisterRow12_aMoveStopsAtTheEdgesOfTheScreen() {
        // Medium is 4 points: the bounds are 2 points around the rectangle of the drag.
        let rectangle = mark(.rectangle, .medium, [point(20, 10), point(60, 40)])
        #expect(rectangle.bounds == CGRect(x: 18, y: 8, width: 44, height: 34))
        #expect(rectangle.outline == CGRect(x: 15, y: 5, width: 50, height: 40))
        #expect(rectangle.moved(by: point(10, 5), in: screen).points == [point(30, 15), point(70, 45)])
        // A move uses whole points, so a sharp line stays sharp.
        #expect(rectangle.moved(by: point(10.4, 4.6), in: screen).points == [point(30, 15), point(70, 45)])
        #expect(rectangle.moved(by: point(900, 900), in: screen).points == [point(58, 28), point(98, 58)])
        #expect(rectangle.moved(by: point(-900, -900), in: screen).points == [point(2, 2), point(42, 32)])
        #expect(rectangle.moved(by: point(900, -3), in: screen).points == [point(58, 7), point(98, 37)])

        // Each kind of mark: in each direction the bounds stop at the edge, and the shape stays.
        let marks = [
            rectangle,
            mark(.ellipse, .thick, [point(60, 40), point(30, 20)]),
            mark(.arrow, .thick, [point(30, 20), point(60, 40)]),
            mark(.line, .thick, [point(30, 20), point(60, 40)]),
            mark(.pen, .thick, [point(30, 20), point(45, 35), point(60, 25)]),
            mark(.highlight, .thick, [point(30, 30), point(60, 32)]),
            text("Hi", at: point(30, 15)),
            mark(.stamp, .medium, [point(50, 30)]),
        ]
        for mark in marks {
            let start = mark.bounds
            #expect(start.minX > 0 && start.minY > 0 && start.maxX < screen.width && start.maxY < screen.height, "\(mark.tool)")
            let far = mark.moved(by: point(900, 900), in: screen)
            let near = mark.moved(by: point(-900, -900), in: screen)
            if mark.tool == .text {
                // A text stays on whole points, so it stops less than 1 point before the edge.
                #expect(far.bounds.maxX <= 100 && far.bounds.maxX > 99 && far.bounds.maxY <= 60 && far.bounds.maxY > 59)
                // Its lines break at the right edge of the screen, and it still has the same lines.
                #expect(far.wrapWidth == screen.width - far.points[0].x && near.wrapWidth == 100)
                #expect(far.bounds.size == start.size && near.bounds.size == start.size)
            } else {
                #expect(isNear(far.bounds.maxX, 100) && isNear(far.bounds.maxY, 60), "\(mark.tool)")
            }
            #expect(isNear(near.bounds.minX, 0) && isNear(near.bounds.minY, 0), "\(mark.tool)")
            for moved in [far, near] {
                #expect(isNear(moved.bounds.width, start.width) && isNear(moved.bounds.height, start.height), "\(mark.tool)")
                let shift = CGPoint(x: moved.points[0].x - mark.points[0].x, y: moved.points[0].y - mark.points[0].y)
                #expect(moved.points == mark.points.map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }, "\(mark.tool)")
                #expect(moved.style == mark.style && moved.text == mark.text && moved.number == mark.number)
            }
        }
    }

    /// A drag of a handle of a Rectangle or an Ellipse changes its size, on the screen.
    @Test func sisterRow13_aHandleChangesTheSizeOfARectangleAndOfAnEllipse() {
        let rectangle = mark(.rectangle, .medium, [point(60, 40), point(20, 10)])
        func frame(_ handle: Handle, to target: CGPoint, of mark: Mark? = nil) -> CGRect {
            (mark ?? rectangle).resized(.frame(handle), to: target, in: screen).frame
        }
        // A corner handle changes two edges. An edge handle changes one edge.
        #expect(frame(.bottomRight, to: point(80, 50)) == CGRect(x: 20, y: 10, width: 60, height: 40))
        #expect(frame(.topLeft, to: point(10, 5)) == CGRect(x: 10, y: 5, width: 50, height: 35))
        #expect(frame(.left, to: point(30, 999)) == CGRect(x: 30, y: 10, width: 30, height: 30))
        #expect(frame(.bottom, to: point(-999, 50)) == CGRect(x: 20, y: 10, width: 40, height: 40))
        for handle in Handle.allCases {
            // Each handle moves only its own edges.
            let resized = frame(handle, to: point(50, 30))
            #expect(resized.minX == (handle.horizontal < 0 ? 50 : 20) && resized.minY == (handle.vertical < 0 ? 30 : 10), "\(handle)")
            #expect(resized.maxX == (handle.horizontal > 0 ? 50 : 60) && resized.maxY == (handle.vertical > 0 ? 30 : 40), "\(handle)")
        }
        // The size change stops on the screen: the middle of the line is half a line width inside.
        #expect(frame(.bottomRight, to: point(900, 900)) == CGRect(x: 20, y: 10, width: 78, height: 48))
        #expect(frame(.topLeft, to: point(-900, -900)) == CGRect(x: 2, y: 2, width: 58, height: 38))
        // Through the opposite edge the rectangle turns over, and it stays correct.
        #expect(frame(.left, to: point(90, 25)) == CGRect(x: 60, y: 10, width: 30, height: 30))
        #expect(frame(.bottomRight, to: point(5, 4)) == CGRect(x: 5, y: 4, width: 15, height: 6))
        // The smallest side is 4 points.
        #expect(frame(.right, to: point(21, 25)) == CGRect(x: 20, y: 10, width: 4, height: 30))
        #expect(frame(.bottomRight, to: point(20, 10)) == CGRect(x: 20, y: 10, width: 4, height: 4))
        // Whole points.
        #expect(frame(.bottomRight, to: point(70.4, 44.6)) == CGRect(x: 20, y: 10, width: 50, height: 35))
        // The style and the kind stay.
        let resized = rectangle.resized(.frame(.right), to: point(80, 25), in: screen)
        #expect(resized.tool == .rectangle && resized.style == rectangle.style && resized.points.count == 2)

        // A Thick rectangle that was drawn to the edge of the screen has edges on half points
        // (3.5 points inside). An edge that does not move stays exactly where it is.
        let thick = mark(.rectangle, .thick, [point(20, 10), point(96.5, 56.5)])
        #expect(frame(.topLeft, to: point(30, 20), of: thick) == CGRect(x: 30, y: 20, width: 66.5, height: 36.5))
        #expect(frame(.left, to: point(-900, 0), of: thick) == CGRect(x: 3.5, y: 10, width: 93, height: 46.5))

        // An Ellipse follows the same rules.
        let ellipse = mark(.ellipse, .thin, [point(20, 10), point(60, 40)])
        #expect(frame(.top, to: point(0, -50), of: ellipse) == CGRect(x: 20, y: 1, width: 40, height: 39))
        #expect(frame(.bottomRight, to: point(80, 50), of: ellipse) == CGRect(x: 20, y: 10, width: 60, height: 40))
    }

    /// A drag of an end handle of an Arrow or a Line moves that end. The other end stays.
    @Test func sisterRow14_anEndHandleMovesThatEndOfAnArrowAndOfALine() {
        for tool in [Tool.arrow, .line] {
            let line = mark(tool, .medium, [point(20, 30), point(80, 30)])
            #expect(line.resized(.end(1), to: point(60, 50), in: screen).points == [point(20, 30), point(60, 50)], "\(tool)")
            #expect(line.resized(.end(0), to: point(-50, 500), in: screen).points == [point(2, 58), point(80, 30)], "\(tool)")
            // An end that comes onto the other end: the mark keeps a length of 4 points.
            #expect(line.resized(.end(1), to: point(21, 30), in: screen).points == [point(20, 30), point(24, 30)], "\(tool)")
            #expect(line.resized(.end(1), to: point(20, 30), in: screen) == line, "\(tool)")
        }
    }
}
