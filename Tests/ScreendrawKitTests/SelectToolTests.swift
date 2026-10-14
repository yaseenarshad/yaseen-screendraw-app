import AppKit
@testable import ScreendrawKit
import Testing

/// The Select tool (D14, YAZ-2828), out of sight: rows 2.80 to 2.91. A "sister row" is a scenario
/// row of YAZ-2782, the Select tool of the sister app. Its rows apply here, except the rows of
/// the capture box (23 to 26) and the row of the options row of that toolbar (3).
///
/// The tests use the session with no window, the toolbar view, and the overlay view with events
/// that the test makes. No test shows a window, moves the mouse or presses a key.
@MainActor @Suite struct SelectToolTests {
    private let left = Screens.left.id

    /// A text mark, made as the user makes it: a click with the Text tool, the typing, and Return.
    private func text(_ string: String, at place: CGPoint, in session: DrawSession) throws -> PlacedMark {
        session.selectTool(.text)
        session.click(at: place)
        session.textChanged(string)
        session.completeText()
        return try #require(session.allMarks.last)
    }

    // MARK: The tool

    @Test func row2_80_sisterRow1_selectIsTheFirstToolButtonWithAnArrowPointerAndTheKeyV() throws {
        let stage = ToolbarTests.Stage()
        #expect(Tool.allCases.first == .select && Tool.select.name == "Select")
        let select = try stage.button("Select")
        // It is the first button of the toolbar: no button is before it, to its left or above it.
        let buttons = stage.toolbar.subviews.compactMap { $0 as? ToolbarButton }
        #expect(buttons.allSatisfy { $0.frame.minX >= select.frame.minX && $0.frame.minY >= select.frame.minY })
        // Its picture is the arrow pointer of the system, and its name shows on hover (sister row 1).
        #expect(NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil) != nil)
        #expect(select.image?.accessibilityDescription == "Select")
        #expect(select.toolTip == "Select" && select.accessibilityLabel() == "Select")

        // Its key at the start is V, and the button shows it.
        #expect(ToolbarAction.tool(.select).startKey == "v" && select.key == "V")
        #expect(stage.session.tool == .pen && !select.isOn)
        stage.session.toolbarKey("v")
        #expect(stage.session.tool == .select && select.isOn)
        #expect(stage.selected == ["Select", "Thick", "Red", "Sticky"])
        // The app remembers the tool, as each other tool (row 2.3).
        #expect(stage.fixture.nextStart().tool == .select)
    }

    @Test func sisterRow2_aClickOnSelectSelectsTheToolAndASecondClickKeepsIt() throws {
        let stage = ToolbarTests.Stage()
        try stage.press("Select")
        #expect(stage.session.tool == .select && stage.selected.contains("Select"))
        // In this app a tool is always selected: a second click keeps it, as for the other tools.
        try stage.press("Select")
        #expect(stage.session.tool == .select && stage.selected.contains("Select"))
        // With Select, a drag draws no mark.
        stage.session.drag([point(100, 100), point(300, 200)])
        #expect(stage.session.markCount == 0 && stage.session.draft(on: left) == nil)
        try stage.press("Rectangle")
        #expect(stage.session.tool == .rectangle && !stage.selected.contains("Select"))
    }

    @Test func sisterRow4_aDrawingToolStaysSelectedAfterItsMark() {
        let session = Fixture().session
        for tool in Tool.allCases where tool != .select && tool != .text {
            session.selectTool(tool)
            session.drag([point(100, 100), point(300, 200)])
            #expect(session.tool == tool && session.selectedID == nil, "\(tool)")
        }
        #expect(session.markCount == 7)
    }

    // MARK: To select a mark

    @Test func row2_81_sisterRow8_aClickOnAMarkSelectsItAndAClickOnAnEmptyPlaceRemovesTheSelection() throws {
        let session = Fixture().session
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        let line = session.draw(.pen, [point(400, 100), point(500, 100)])
        let other = session.draw(.pen, [point(50, 50), point(150, 50)], on: Screens.right.id)
        let revision = session.marksRevision
        var changes = 0
        session.onChange = { changes += 1 }

        session.selectTool(.select)
        #expect(session.selectedID == nil && session.selectedMark(on: left) == nil)
        // A click on the line of the rectangle.
        session.click(at: point(100, 150))
        #expect(session.selectedID == rectangle.id)
        #expect(session.selectedMark(on: left) == rectangle.mark && session.selectedMark(on: Screens.right.id) == nil)
        // A click near the Pen line, in its tolerance of 6 points (sister row 5).
        session.click(at: point(450, 109))
        #expect(session.selectedID == line.id)
        // A click inside the rectangle (sister row 6).
        session.click(at: point(200, 150))
        #expect(session.selectedID == rectangle.id)
        // A click on an empty place removes the selection (sister row 8).
        session.click(at: point(600, 400))
        #expect(session.selectedID == nil && session.selectedMark(on: left) == nil)
        // A mark of the other screen is selected by a click on that screen. Only one mark is selected.
        session.click(at: point(100, 150))
        session.click(at: point(100, 50), on: Screens.right.id)
        #expect(session.selectedID == other.id)
        #expect(session.selectedMark(on: Screens.right.id) == other.mark && session.selectedMark(on: left) == nil)

        // A selection changes no mark: the views make no mark layer again, and Undo has no new step.
        #expect(session.marksRevision == revision && session.allMarks == [rectangle, line, other])
        // The views heard of the new tool and of the six changes of the selection. A click that
        // changes nothing tells nothing.
        #expect(changes == 7)
        session.click(at: point(100, 50), on: Screens.right.id)
        #expect(changes == 7)
        for _ in 0..<3 { session.undo() }
        #expect(session.markCount == 0 && !session.canUndo)
    }

    @Test func row2_81_sisterRow9_theSelectedMarkShowsAThinOutlineAndHandles() throws {
        let stage = OverlayViewTests.Stage()
        // A Thick red rectangle, x 90 to 200 and y 80 to 140.
        stage.session.selectTool(.rectangle)
        try stage.drag(from: point(90, 80), to: point(200, 140))
        stage.session.selectTool(.select)
        let plain = stage.pixels()
        let blue = Pixel(red: 26, green: 140, blue: 255, alpha: 255)
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)

        try stage.click(at: point(90, 110))
        #expect(stage.session.selectedID != nil)
        let selected = stage.pixels()
        // Eight handles, on the corners and the edge middles of the rectangle (sister row 10).
        // Each one is a white square of 7 points with a blue edge, so it shows on a light and on a dark screen.
        for (x, y) in [(90, 80), (145, 80), (200, 80), (200, 110), (200, 140), (145, 140), (90, 140), (90, 110)] as [(CGFloat, CGFloat)] {
            #expect(stage.pixel(x, y, in: selected) == white, "the handle at \(x), \(y)")
            #expect(stage.pixel(x - 2, y - 2, in: selected) == white, "the handle at \(x), \(y)")
            #expect(stage.pixel(x - 3.5, y, in: selected).isNear(blue), "the edge of the handle at \(x), \(y)")
            #expect(stage.pixel(x + 2.5, y, in: selected).isNear(blue), "the edge of the handle at \(x), \(y)")
            #expect(stage.pixel(x, y, in: plain) == Pixel(.red))
        }
        // The outline is 3 points outside the bounds of the mark: its top line is at y 73, pixel
        // rows 146 and 147. It is thin and dashed: white pixels and blue pixels (sister row 9).
        var whitePixels = 0, dashes = 0
        for x in 170..<410 {
            for y in [146, 147] {
                if selected[x, y] == white {
                    whitePixels += 1
                } else if selected[x, y].isNear(blue) {
                    dashes += 1
                } else {
                    Issue.record("The pixel \(x), \(y) is not a pixel of the outline: \(selected[x, y])")
                    return
                }
                #expect(plain[x, y] == .clear)
            }
            // The line is 1 point: the rows above and below it show the screen.
            #expect(selected[x, 145] == .clear && selected[x, 148] == .clear)
        }
        #expect(whitePixels > 100 && dashes > 100)
        // The left, the right and the bottom line of the outline.
        for (x, y) in [(166, 220), (413, 220), (300, 293)] {
            #expect(selected[x, y] == white || selected[x, y].isNear(blue), "the outline at \(x), \(y)")
        }

        // A click on an empty place: the overlay shows the mark alone again.
        try stage.click(at: point(300, 250))
        #expect(stage.session.selectedID == nil)
        let after = stage.pixels()
        var differences = 0
        for y in 0..<after.height {
            for x in 0..<after.width where after[x, y] != plain[x, y] { differences += 1 }
        }
        #expect(differences == 0)
    }

    @Test func sisterRow10_aLineAndAnArrowShowOneHandleAtEachEndAndAPenMarkShowsNone() throws {
        let stage = OverlayViewTests.Stage()
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
        stage.session.setSize(.thin)
        stage.session.selectTool(.line)
        try stage.drag(from: point(50, 50), to: point(150, 50))
        stage.session.selectTool(.arrow)
        try stage.drag(from: point(50, 120), to: point(150, 120))
        stage.session.selectTool(.pen)
        try stage.drag(from: point(50, 200), to: point(150, 200))
        stage.session.selectTool(.select)

        for y in [50, 120] as [CGFloat] {
            try stage.click(at: point(100, y))
            let pixels = stage.pixels()
            // A white handle at each end, and none at the middle of the line.
            #expect(stage.pixel(50, y - 2, in: pixels) == white && stage.pixel(150, y - 2, in: pixels) == white)
            #expect(stage.pixel(100, y - 2, in: pixels) == .clear)
        }
        try stage.click(at: point(100, 200))
        let pixels = stage.pixels()
        #expect(stage.session.selectedID != nil)
        // The Pen mark has the outline only.
        #expect(stage.pixel(50, 197.5, in: pixels) == .clear && stage.pixel(150, 197.5, in: pixels) == .clear)
        #expect(stage.pixel(100, 196.5, in: pixels) != .clear)
    }

    // MARK: To move and to change a mark

    @Test func row2_82_sisterRow11_aDragMovesTheSelectedMarkAndItCannotLeaveItsScreen() throws {
        let session = Fixture().session
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        session.selectTool(.select)

        // A drag that starts on a mark that is not selected selects it and moves it in one step (sister row 11).
        session.pointerDown(at: point(100, 150), on: left)
        #expect(session.selectedID == rectangle.id)
        session.pointerDragged(to: point(120, 160))
        // During the drag the mark of the drag shows, and the list of marks does not change.
        #expect(session.changedMark(on: left)?.mark.points == [point(120, 110), point(320, 210)])
        #expect(session.changedMark(on: left)?.id == rectangle.id && session.changedMark(on: Screens.right.id) == nil)
        #expect(session.selectedMark(on: left)?.points == [point(120, 110), point(320, 210)])
        #expect(session.marks(on: left) == [rectangle])
        // A drag that moves draws no new mark.
        #expect(session.draft(on: left) == nil)
        session.pointerUp(at: point(150, 180))
        #expect(session.marks(on: left).map { $0.mark.points } == [[point(150, 130), point(350, 230)]])
        #expect(session.selectedID == rectangle.id && session.changedMark(on: left) == nil)
        // The mark is the same mark: its id, its style, its stay value and its clock stay.
        let moved = try #require(session.marks(on: left).first)
        #expect(moved.id == rectangle.id && moved.mark.style == rectangle.mark.style)
        #expect(moved.stay == rectangle.stay && moved.shownAt == rectangle.shownAt)

        // A drag of the selected mark. It starts on the line, between two handles.
        session.drag([point(150, 150), point(140, 145)])
        #expect(session.marks(on: left).map { $0.mark.points } == [[point(140, 125), point(340, 225)]])

        // The mark cannot leave its screen (sister row 12): the move stops when the bounds touch an edge.
        // The pointer goes far to the right, onto the next screen. The mark stays on the left screen.
        session.drag([point(140, 150), point(5000, 5000)])
        var bounds = try #require(session.marks(on: left).first).mark.bounds
        #expect(bounds.maxX == 800 && bounds.maxY == 600 && bounds.size == rectangle.mark.bounds.size)
        #expect(session.marks(on: Screens.right.id).isEmpty && session.markCount == 1)
        session.drag([point(650, 596.5), point(-5000, -5000)])
        bounds = try #require(session.marks(on: left).first).mark.bounds
        #expect(bounds.minX == 0 && bounds.minY == 0 && bounds.size == rectangle.mark.bounds.size)
    }

    @Test func sisterRow15_aDragOfLessThan3PointsChangesNothingAndOnlySelects() {
        let session = Fixture().session
        #expect(DrawSession.minimumDrag == 3)
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        session.selectTool(.select)
        let revision = session.marksRevision

        session.drag([point(100, 150), point(102, 151), point(101, 152)])
        #expect(session.selectedID == rectangle.id)
        #expect(session.marks(on: left) == [rectangle] && session.marksRevision == revision)
        // The same for a handle of the selected mark.
        session.drag([point(300, 200), point(302, 201)])
        #expect(session.marks(on: left) == [rectangle] && session.marksRevision == revision)
        // No Undo step was made: one Undo removes the mark.
        session.undo()
        #expect(session.markCount == 0 && !session.canUndo)

        // After 3 points the mark follows the pointer from the place of the pointer down.
        session.redo()
        session.selectTool(.select)
        session.pointerDown(at: point(100, 150), on: left)
        session.pointerDragged(to: point(102, 150))
        #expect(session.changedMark(on: left) == nil)
        session.pointerDragged(to: point(103, 150))
        #expect(session.changedMark(on: left)?.mark.points == [point(103, 100), point(303, 200)])
        session.pointerUp(at: point(103, 150))
    }

    @Test func row2_83_aHandleChangesARectangleAnEllipseAnArrowAndALineAndTheOtherMarksOnlyMove() throws {
        let session = Fixture().session
        func points(_ placed: PlacedMark) -> [CGPoint] {
            session.allMarks.first { $0.id == placed.id }?.mark.points ?? []
        }

        // A Rectangle: the bottom right handle. The pointer down is 2 and 3 points from the
        // handle, and the handle keeps that distance (sister row 13).
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        session.selectTool(.select)
        session.click(at: point(200, 150))
        #expect(session.selectedID == rectangle.id)
        session.pointerDown(at: point(302, 203), on: left)
        session.pointerDragged(to: point(352, 233))
        #expect(session.changedMark(on: left)?.mark.points == [point(100, 100), point(350, 230)])
        #expect(session.marks(on: left) == [rectangle])
        session.pointerUp(at: point(402, 253))
        #expect(points(rectangle) == [point(100, 100), point(400, 250)])
        // An edge handle changes one edge.
        session.drag([point(100, 175), point(60, 400)])
        #expect(points(rectangle) == [point(60, 100), point(400, 250)])

        // An Ellipse follows the same rules.
        let ellipse = session.draw(.ellipse, [point(500, 100), point(700, 200)])
        session.selectTool(.select)
        session.click(at: point(600, 100))
        #expect(session.selectedID == ellipse.id)
        session.drag([point(600, 100), point(600, 60)])
        #expect(points(ellipse) == [point(500, 60), point(700, 200)])
        // The size change stops at the edge of the screen: half a line of 7 points before it.
        session.drag([point(700, 130), point(5000, 130)])
        #expect(points(ellipse) == [point(500, 60), point(796.5, 200)])

        // An Arrow and a Line: a handle at each end. That end moves, and the other end stays (sister row 14).
        let arrow = session.draw(.arrow, [point(100, 300), point(300, 300)])
        let line = session.draw(.line, [point(100, 400), point(300, 400)])
        session.selectTool(.select)
        session.click(at: point(200, 300))
        session.drag([point(300, 300), point(350, 340)])
        #expect(points(arrow) == [point(100, 300), point(350, 340)])
        session.click(at: point(200, 400))
        session.drag([point(100, 400), point(80, 450)])
        #expect(points(line) == [point(80, 450), point(300, 400)])
        #expect(session.marks(on: left).map { $0.mark.tool } == [.rectangle, .ellipse, .arrow, .line])

        // A Pen mark, a Highlight mark, a Text and a Stamp have no handle. A drag from an end or
        // a corner moves the mark, and its shape and its size stay.
        let pen = session.draw(.pen, [point(500, 300), point(550, 320), point(600, 300)])
        let highlight = session.draw(.highlight, [point(500, 400), point(600, 400)])
        let label = try text("Hello", at: point(500, 500), in: session)
        session.selectTool(.stamp)
        session.click(at: point(300, 500))
        let stamp = try #require(session.allMarks.last)
        session.selectTool(.select)
        for (placed, start) in [(pen, point(500, 300)), (highlight, point(600, 400)), (label, point(502, 487)), (stamp, point(300, 500))] {
            session.click(at: start)
            #expect(session.selectedID == placed.id, "\(placed.mark.tool)")
            #expect(session.selectedMark(on: left)?.handles.isEmpty == true, "\(placed.mark.tool)")
            session.drag([start, point(start.x + 30, start.y - 20)])
            let moved = try #require(session.allMarks.first { $0.id == placed.id }).mark
            #expect(moved.points == placed.mark.points.map { point($0.x + 30, $0.y - 20) }, "\(placed.mark.tool)")
            #expect(moved.bounds.size == placed.mark.bounds.size && moved.style == placed.mark.style, "\(placed.mark.tool)")
            #expect(moved.text == placed.mark.text && moved.number == placed.mark.number)
        }
    }

    @Test func row2_84_sisterRow17_aSizeOrColourButtonOrItsKeyChangesTheSelectedMark() throws {
        let stage = ToolbarTests.Stage()
        let session = stage.session
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        let line = session.draw(.pen, [point(400, 100), point(500, 100)])
        func style(_ placed: PlacedMark) -> MarkStyle? {
            session.allMarks.first { $0.id == placed.id }?.mark.style
        }
        session.selectTool(.select)
        session.click(at: point(100, 150))

        // A colour button and a size button change the selected mark. The other mark does not change (row 2.10).
        try stage.press("Blue")
        #expect(style(rectangle) == MarkStyle(color: .blue, size: .thick))
        try stage.press("Thin")
        #expect(style(rectangle) == MarkStyle(color: .blue, size: .thin))
        #expect(style(line) == MarkStyle(color: .red, size: .thick))
        // The keys do the same as the buttons.
        session.toolbarKey("6")
        session.toolbarKey("2")
        #expect(style(rectangle) == MarkStyle(color: .green, size: .medium))
        #expect(style(line) == MarkStyle(color: .red, size: .thick))
        #expect(session.selectedID == rectangle.id && session.tool == .select)
        // The place of the mark stays.
        #expect(session.marks(on: left).first?.mark.points == rectangle.mark.points)

        // It is also the size and the colour of the next mark, and the app remembers it (sister row 17).
        #expect(stage.fixture.nextStart().style == MarkStyle(color: .green, size: .medium))
        session.selectTool(.pen)
        session.drag([point(400, 300), point(500, 300)])
        #expect(session.allMarks.last?.mark.style == MarkStyle(color: .green, size: .medium))

        // The toolbar shows the size and the colour of the selected mark. With no selection it
        // shows the size and the colour of the next mark.
        session.selectTool(.select)
        #expect(stage.selected == ["Select", "Medium", "Green", "Sticky"])
        session.click(at: point(450, 100))
        #expect(session.selectedID == line.id && session.style == MarkStyle(color: .red, size: .thick))
        #expect(stage.selected == ["Select", "Thick", "Red", "Sticky"])
        session.click(at: point(700, 500))
        #expect(stage.selected == ["Select", "Medium", "Green", "Sticky"])

        // The size or the colour that the mark has already: nothing changes, and Undo gets no step.
        session.click(at: point(450, 100))
        let revision = session.marksRevision
        try stage.press("Red")
        #expect(session.marksRevision == revision && style(line) == MarkStyle(color: .red, size: .thick))
    }

    @Test func row2_84_aThickerLineKeepsTheSelectedMarkOnItsScreen() throws {
        let session = Fixture().session
        session.setSize(.thin)
        // A Thin rectangle that was drawn into the corner of the screen: its line is 1 point from the edges.
        let rectangle = session.draw(.rectangle, [point(700, 500), point(900, 900)])
        #expect(rectangle.mark.points == [point(700, 500), point(799, 599)])
        session.selectTool(.select)
        session.click(at: point(700, 550))
        session.setSize(.thick)
        // A line of 7 points reaches past the edge. The mark moves in, and its size stays.
        let thick = try #require(session.marks(on: left).first).mark
        #expect(thick.points == [point(697.5, 497.5), point(796.5, 596.5)])
        #expect(thick.bounds.maxX == 800 && thick.bounds.maxY == 600)
    }

    @Test func sisterRow18_forATextMarkASizeButtonChangesTheFontSize() throws {
        let stage = ToolbarTests.Stage()
        let session = stage.session
        let label = try text("Hello", at: point(200, 200), in: session)
        #expect(label.mark.style.fontSize == 24)
        session.selectTool(.select)
        session.click(at: point(210, 200))
        #expect(session.selectedID == label.id)

        try stage.press("Thin")
        try stage.press("Blue")
        let small = try #require(session.marks(on: left).first).mark
        #expect(small.style == MarkStyle(color: .blue, size: .thin) && small.style.fontSize == 14)
        #expect(small.text == "Hello" && small.points == label.mark.points)
        // The letters are smaller, so the outline of the selected mark is smaller.
        #expect(small.bounds.height < label.mark.bounds.height && small.bounds.width < label.mark.bounds.width)
    }

    @Test func row2_85_sisterRow19_aDoubleClickOnATextMarkOpensItsTextAgain() throws {
        let stage = OverlayViewTests.Stage()
        let view = stage.view, session = stage.session
        session.selectTool(.text)
        try stage.click(at: point(100, 100))
        var field = try #require(view.textView)
        field.insertText("Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let label = try #require(session.marks(on: stage.display.id).first)
        #expect(label.mark.text == "Hello" && label.mark.points == [point(100, 85)])
        let shown = stage.pixels().inkCount(x: 200..<400, y: 170..<230)
        #expect(shown > 100)

        // With a drawing tool, a double-click opens nothing.
        session.selectTool(.select)
        #expect(view.textView == nil)
        // A double-click on the text: its field opens with the old text (sister row 19).
        try stage.doubleClick(at: point(110, 100))
        field = try #require(view.textView)
        #expect(field.string == "Hello" && field.frame.minX == 100 && field.font?.pointSize == 24)
        #expect(field.selectedRange() == NSRange(location: 5, length: 0))
        #expect(session.textEdit?.markID == label.id && session.selectedID == label.id)
        // The text shows in its field, not as a mark. The mark is still in the list, and it has no outline now.
        #expect(view.markLayers[label.id]?.isHidden == true && session.markCount == 1)
        #expect(session.selectedMark(on: stage.display.id) == nil)
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)

        // The typing changes the text, and Return finishes it. The mark is the same mark.
        field.insertText(" there", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.textView == nil)
        var marks = session.marks(on: stage.display.id)
        #expect(marks.map { $0.mark.text } == ["Hello there"] && marks.first?.id == label.id)
        #expect(marks.first?.mark.points == label.mark.points && marks.first?.mark.style == label.mark.style)
        #expect(view.markLayers[label.id]?.isHidden == false)
        #expect(stage.pixels().inkCount(x: 200..<600, y: 170..<230) > shown)
        // The mark stays selected, and the change of the text is one Undo step (row 2.89).
        #expect(session.selectedID == label.id)
        session.undo()
        #expect(session.marks(on: stage.display.id).map { $0.mark.text } == ["Hello"])
        session.redo()
        #expect(session.marks(on: stage.display.id).map { $0.mark.text } == ["Hello there"])

        // Esc while the text is open again: the field closes and the old text stays.
        try stage.doubleClick(at: point(110, 100))
        field = try #require(view.textView)
        field.insertText("!!!", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        marks = session.marks(on: stage.display.id)
        #expect(view.textView == nil && marks.map { $0.mark.text } == ["Hello there"])
        #expect(view.markLayers[label.id]?.isHidden == false && session.mode == .drawing && session.selectedID == label.id)

        // A click at a different place also finishes the text.
        try stage.doubleClick(at: point(110, 100))
        try #require(view.textView).insertText("?", replacementRange: NSRange(location: NSNotFound, length: 0))
        try stage.click(at: point(300, 250))
        #expect(view.textView == nil && session.marks(on: stage.display.id).map { $0.mark.text } == ["Hello there?"])

        // An empty text removes the mark. One Undo brings it back.
        try stage.doubleClick(at: point(110, 100))
        field = try #require(view.textView)
        field.selectAll(nil)
        field.insertText("  ", replacementRange: field.selectedRange())
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(session.markCount == 0 && session.selectedID == nil && view.markLayers.isEmpty)
        session.undo()
        #expect(session.marks(on: stage.display.id).map { $0.mark.text } == ["Hello there?"])

        // A double-click on a mark that is no Text opens nothing.
        session.selectTool(.rectangle)
        try stage.drag(from: point(50, 200), to: point(150, 280))
        session.selectTool(.select)
        try stage.doubleClick(at: point(50, 240))
        #expect(view.textView == nil && session.textEdit == nil && session.selectedID != nil)
    }

    // MARK: Delete and Esc

    @Test func row2_86_sisterRow16_deleteRemovesOnlyTheSelectedMarkAndWithNoSelectionItClearsAll() throws {
        let stage = OverlayViewTests.Stage()
        let view = stage.view, session = stage.session, id = stage.display.id
        try stage.drag(from: point(50, 50), to: point(250, 50))
        try stage.drag(from: point(50, 100), to: point(250, 100))
        try stage.drag(from: point(50, 150), to: point(250, 150))
        let marks = session.marks(on: id)
        session.selectTool(.select)

        // Delete with a selected mark: only that mark goes away (sister row 16).
        try stage.click(at: point(150, 100))
        #expect(session.selectedID == marks[1].id)
        view.keyDown(with: try stage.key(51))
        #expect(session.marks(on: id) == [marks[0], marks[2]])
        #expect(session.selectedID == nil && session.mode == .drawing)
        #expect(Set(view.markLayers.keys) == [marks[0].id, marks[2].id])
        // Forward Delete does the same.
        try stage.click(at: point(150, 150))
        view.keyDown(with: try stage.key(117))
        #expect(session.marks(on: id) == [marks[0]])

        // Undo brings a deleted mark back at its old place among the marks.
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(session.marks(on: id).map { $0.id } == marks.map { $0.id })

        // With no selection, Delete clears all the marks (row 2.20). Drawing stays on.
        #expect(session.selectedID == nil)
        view.keyDown(with: try stage.key(51))
        #expect(session.markCount == 0 && session.mode == .drawing)
        // One Undo brings them back (row 2.21).
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(session.markCount == 3)
        // With a selected mark, the Clear all button still clears all.
        try stage.click(at: point(150, 100))
        session.clearAll()
        #expect(session.markCount == 0 && session.selectedID == nil)
    }

    @Test func row2_87_sisterRow22_escRemovesOnlyTheSelectionAndTheNextEscClearsAllAndStops() throws {
        let stage = OverlayViewTests.Stage()
        let view = stage.view, session = stage.session
        try stage.drag(from: point(50, 50), to: point(250, 50))
        try stage.drag(from: point(50, 100), to: point(250, 100))
        session.selectTool(.select)
        try stage.click(at: point(150, 100))
        let revision = session.marksRevision
        #expect(session.selectedID != nil)

        // Esc with a selected mark: only the selection goes away (sister row 22).
        view.keyDown(with: try stage.key(53))
        #expect(session.selectedID == nil && session.mode == .drawing)
        #expect(session.markCount == 2 && session.marksRevision == revision && session.tool == .select)
        // The next Esc clears all and stops (row 4.8).
        view.keyDown(with: try stage.key(53))
        #expect(session.mode == .off && session.markCount == 0)
    }

    @Test func row2_88_aDifferentToolClickThroughAndModeOffRemoveTheSelection() throws {
        let stage = OverlayViewTests.Stage()
        let session = stage.session
        session.selectTool(.rectangle)
        try stage.drag(from: point(90, 80), to: point(200, 140))
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
        func selectTheMark() throws {
            if session.mode == .off { session.start(displays: [stage.display]) }
            if session.mode == .clickThrough { session.toggleClickThrough() }
            session.selectTool(.select)
            try stage.click(at: point(90, 110))
            #expect(session.selectedID != nil)
            #expect(stage.pixel(90, 80, in: stage.pixels()) == white)
        }
        /// The selection is gone, in the session and on the overlay. The mark stays.
        func expectNoSelection(_ what: Comment) {
            #expect(session.selectedID == nil && session.selectedMark(on: stage.display.id) == nil, what)
            #expect(stage.pixel(90, 80, in: stage.pixels()) == Pixel(.red), what)
            #expect(session.markCount == 1, what)
        }

        // A click on the Select button keeps the selection.
        try selectTheMark()
        session.selectTool(.select)
        #expect(session.selectedID != nil)
        // A different tool, by its button or by its key.
        session.selectTool(.pen)
        expectNoSelection("a different tool")
        try selectTheMark()
        stage.view.keyDown(with: try stage.key(0, "a"))
        #expect(session.tool == .arrow)
        expectNoSelection("the key of a different tool")

        // Click-through. The selection does not come back in mode drawing.
        try selectTheMark()
        session.toggleClickThrough()
        #expect(session.mode == .clickThrough)
        expectNoSelection("click-through")
        session.toggleClickThrough()
        expectNoSelection("back in mode drawing")

        // Mode off, by the draw hotkey or the Close button. The Sticky mark is kept, with no selection.
        try selectTheMark()
        session.stop()
        #expect(session.mode == .off && session.selectedID == nil && session.markCount == 1)
        session.start(displays: [stage.display])
        expectNoSelection("the next start of drawing")
    }

    // MARK: Undo, and the clocks

    @Test func row2_89_sisterRows20And21_aMoveASizeChangeAStyleChangeAndADeleteAreOneUndoStepEach() throws {
        let session = Fixture().session
        let first = session.draw(.rectangle, [point(100, 100), point(300, 200)]).mark
        session.draw(.pen, [point(400, 400), point(500, 400)])
        session.selectTool(.select)
        var states = [try #require(session.marks(on: left).first).mark]
        func record() throws {
            states.append(try #require(session.marks(on: left).first).mark)
        }

        // A move: one drag with many pointer moves is one step (sister row 21).
        session.pointerDown(at: point(100, 150), on: left)
        for x in stride(from: 105, through: 200, by: 5) { session.pointerDragged(to: point(CGFloat(x), 150)) }
        session.pointerUp(at: point(200, 150))
        try record()
        // A size change.
        session.drag([point(400, 200), point(450, 260)])
        try record()
        // Two style changes.
        session.setColor(.blue)
        try record()
        session.setSize(.thin)
        try record()
        #expect(states.map { $0.points } == [
            [point(100, 100), point(300, 200)], [point(200, 100), point(400, 200)],
            [point(200, 100), point(450, 260)], [point(200, 100), point(450, 260)], [point(200, 100), point(450, 260)],
        ])
        #expect(states.map { $0.style.color } == [.red, .red, .red, .blue, .blue])
        #expect(states.map { $0.style.size } == [.thick, .thick, .thick, .thick, .thin])
        // A delete.
        session.delete()
        #expect(session.marks(on: left).map { $0.mark.tool } == [.pen])

        // Undo takes back one change at a time (sister row 20): the delete, the two style changes,
        // the size change and the move. The rectangle comes back below the Pen mark.
        session.undo()
        #expect(session.marks(on: left).map { $0.mark.tool } == [.rectangle, .pen])
        for state in states.reversed() {
            #expect(session.marks(on: left).first?.mark == state)
            session.undo()
        }
        // The last Undo took back the Pen mark. One more takes back the rectangle.
        #expect(session.marks(on: left).map { $0.mark } == [first])
        session.undo()
        #expect(session.markCount == 0 && !session.canUndo)

        // Redo puts each change back, in the same order.
        session.redo()
        session.redo()
        for state in states.dropFirst() {
            session.redo()
            #expect(session.marks(on: left).first?.mark == state)
        }
        session.redo()
        #expect(session.marks(on: left).map { $0.mark.tool } == [.pen] && !session.canRedo)

        // A new change empties the Redo list.
        session.undo()
        session.undo()
        #expect(session.canRedo)
        session.selectTool(.select)
        session.drag([point(200, 150), point(210, 150)])
        #expect(!session.canRedo)
        // The selected mark stays selected after Undo while it exists. It is not selected when Undo removed it.
        #expect(session.selectedID != nil)
        session.undo()
        #expect(session.selectedID != nil)
        session.undo()
        session.undo()
        session.undo()
        session.undo()
        #expect(session.markCount == 1 && session.selectedID != nil)
        session.undo()
        session.undo()
        #expect(session.markCount == 0 && session.selectedID == nil)
    }

    @Test func row2_90_aFadeOrHoldMarkCanBeSelectedAndAMoveDoesNotStartItsClockAgain() throws {
        // A Fade mark of 2 seconds: full strength for 1 second, then it fades for 1 second.
        var fixture = Fixture()
        var session = fixture.session
        session.setStay(.fade)
        let fade = session.draw(.pen, [point(100, 100), point(300, 100)])
        session.selectTool(.select)
        fixture.clock.time += 0.5
        session.drag([point(200, 100), point(200, 200)])
        var moved = try #require(session.marks(on: left).first)
        #expect(session.selectedID == fade.id && moved.mark.points == [point(100, 200), point(300, 200)])
        // The clock of the mark did not start again.
        #expect(moved.shownAt == fade.shownAt && moved.stay == .fade)
        fixture.clock.time += 1
        #expect(session.opacity(of: moved) == 0.5)
        // The mark is visible, so a click still selects it.
        session.click(at: point(600, 500))
        session.click(at: point(200, 200))
        #expect(session.selectedID == fade.id)
        // Its clock removes it: the selection goes away with it.
        fixture.clock.time += 0.5
        session.tick()
        #expect(session.markCount == 0 && session.selectedID == nil && session.selectedMark(on: left) == nil)
        #expect(!session.canUndo)

        // Hold marks of 5 seconds. With Select, a pointer down, a drag and a pointer up are no
        // drawing activity: the common clock does not start again.
        fixture = Fixture()
        session = fixture.session
        session.setStay(.hold)
        let hold = session.draw(.pen, [point(100, 100), point(300, 100)])
        session.selectTool(.select)
        fixture.clock.time += 4
        session.drag([point(200, 100), point(200, 200)])
        session.setColor(.blue)
        moved = try #require(session.marks(on: left).first)
        #expect(session.selectedID == hold.id && moved.mark.points == [point(100, 200), point(300, 200)])
        fixture.clock.time += 1.5
        #expect(session.opacity(of: moved) == 0.5)

        // The clock removes the mark in the middle of a drag: the drag ends, and nothing is selected.
        session.pointerDown(at: point(200, 200), on: left)
        session.pointerDragged(to: point(250, 250))
        #expect(session.changedMark(on: left) != nil)
        fixture.clock.time += 0.5
        session.tick()
        #expect(session.markCount == 0 && session.selectedID == nil && session.changedMark(on: left) == nil)
        session.pointerDragged(to: point(300, 300))
        session.pointerUp(at: point(300, 300))
        #expect(session.markCount == 0 && !session.canUndo && !session.hasTimedMarks)

        // The clock removes a Text mark while its text is open again: the field closes.
        fixture = Fixture()
        session = fixture.session
        session.setStay(.fade)
        let label = try text("Hello", at: point(200, 200), in: session)
        session.selectTool(.select)
        session.click(at: point(210, 200))
        session.doubleClick(at: point(210, 200), on: left)
        #expect(session.textEdit?.markID == label.id)
        fixture.clock.time += 2
        session.tick()
        #expect(session.textEdit == nil && session.markCount == 0 && session.selectedID == nil)
    }

    @Test func row2_91_theSwitchDoesNotChangeTheSelectedMark() throws {
        let stage = ToolbarTests.Stage()
        let session = stage.session
        let sticky = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        session.selectTool(.select)
        session.click(at: point(100, 150))
        let revision = session.marksRevision

        // The switch is for new marks only (row 3.7).
        try stage.press("Fade")
        #expect(session.stay == .fade && session.selectedID == sticky.id)
        #expect(session.marks(on: left) == [sticky] && session.marksRevision == revision)
        #expect(!session.hasTimedMarks)
        session.toolbarKey("g")
        #expect(session.stay == .hold && session.marks(on: left) == [sticky] && !session.hasTimedMarks)
        // A move of the selected mark does not give it the value of the switch.
        session.drag([point(100, 125), point(150, 125)])
        #expect(session.marks(on: left).map { $0.mark.points } == [[point(150, 100), point(350, 200)]])
        #expect(session.marks(on: left).map { $0.stay } == [.sticky])
        // The next mark has the value of the switch.
        let hold = session.draw(.pen, [point(400, 400), point(500, 400)])
        #expect(session.marks(on: left).map { $0.stay } == [.sticky, .hold])

        // A selected Hold mark keeps its value and its clock when the switch changes.
        session.selectTool(.select)
        session.click(at: point(450, 400))
        #expect(session.selectedID == hold.id)
        stage.fixture.clock.time += 5.5
        try stage.press("Sticky")
        try stage.press("Fade")
        let selected = try #require(session.marks(on: left).last)
        #expect(selected.stay == .hold && session.opacity(of: selected) == 0.5)
        stage.fixture.clock.time += 0.5
        session.tick()
        #expect(session.marks(on: left).map { $0.stay } == [.sticky] && session.selectedID == nil)
    }

    // MARK: The cost and the pointer

    /// A move or a size change of one mark makes only the layer of that mark again.
    @Test func aMoveOfOneMarkDoesNotDrawTheOtherMarksAgain() throws {
        let stage = OverlayViewTests.Stage()
        let view = stage.view, session = stage.session, id = stage.display.id
        try stage.drag(from: point(50, 50), to: point(250, 50))
        session.selectTool(.rectangle)
        try stage.drag(from: point(90, 100), to: point(200, 160))
        session.selectTool(.text)
        try stage.click(at: point(100, 230))
        session.textChanged("Hello")
        session.completeText()
        let marks = session.marks(on: id)
        let layers = view.markLayers
        #expect(layers.count == 3)
        session.selectTool(.select)

        // The move of the rectangle: 20 pointer moves.
        let revision = session.marksRevision
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 90, 130))
        var seen: [CALayer] = []
        for step in 1...20 {
            view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 90 + CGFloat(step) * 5, 130))
            // The other marks keep their layers, and the list of marks did not change.
            #expect(view.markLayers[marks[0].id] === layers[marks[0].id] && view.markLayers[marks[2].id] === layers[marks[2].id])
            #expect(session.marksRevision == revision)
            seen.append(try #require(view.markLayers[marks[1].id]))
        }
        // The mark of the drag got a new layer for each move, at the place of the pointer.
        #expect(Set(seen.map { ObjectIdentifier($0) }).count == 20 && !seen.contains { $0 === layers[marks[1].id] })
        var pixels = stage.pixels()
        #expect(stage.pixel(190, 115, in: pixels) == Pixel(.red) && stage.pixel(90, 115, in: pixels) == .clear)
        // The outline and the handles follow the mark during the drag.
        #expect(stage.pixel(190, 97.5, in: pixels) == Pixel(red: 255, green: 255, blue: 255, alpha: 255))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 190, 130))
        // The release makes no layer again: the last layer of the drag shows the final mark.
        #expect(seen.last === view.markLayers[marks[1].id])
        #expect(view.markLayers[marks[0].id] === layers[marks[0].id] && view.markLayers[marks[2].id] === layers[marks[2].id])
        #expect(session.marks(on: id)[1].mark.points == [point(190, 100), point(300, 160)])
        // The marks keep their order: the layer of the rectangle is between the two other layers.
        #expect(view.markLayers.count == 3)
        let order = try #require(view.canvasLayer.sublayers?.first?.sublayers)
        #expect(order.count == 4 && order[0] === view.markLayers[marks[0].id] && order[1] === view.markLayers[marks[1].id])
        #expect(order[2] === view.markLayers[marks[2].id] && order[3] === view.draftLayer)

        // A size change of the rectangle and a style change also leave the other layers.
        try stage.drag(from: point(300, 160), to: point(320, 180))
        session.setColor(.blue)
        pixels = stage.pixels()
        #expect(stage.pixel(320, 150, in: pixels) == Pixel(.blue))
        #expect(view.markLayers[marks[0].id] === layers[marks[0].id] && view.markLayers[marks[2].id] === layers[marks[2].id])
        // A new selection makes no layer of a mark again.
        let rectangleLayer = view.markLayers[marks[1].id]
        try stage.click(at: point(150, 50))
        try stage.click(at: point(350, 280))
        #expect(view.markLayers[marks[1].id] === rectangleLayer && view.markLayers[marks[0].id] === layers[marks[0].id])
    }

    @Test func withSelectThePointerShapeTellsWhatADragDoes() throws {
        let session = Fixture().session
        let rectangle = session.draw(.rectangle, [point(100, 100), point(300, 200)])
        session.draw(.arrow, [point(100, 300), point(300, 300)])
        // With a drawing tool the shape does not depend on the place.
        #expect(session.pointerShape(at: point(100, 150), on: left) == .crosshair)

        session.selectTool(.select)
        // The arrow on an empty place, and the open hand on a mark.
        #expect(session.pointerShape(at: point(600, 500), on: left) == .arrow)
        #expect(session.pointerShape(at: point(100, 150), on: left) == .openHand)
        #expect(session.pointerShape(at: point(200, 150), on: left) == .openHand)
        // The marks of a different screen do not count.
        #expect(session.pointerShape(at: point(100, 150), on: Screens.right.id) == .arrow)
        // A mark that is not selected has no handle.
        #expect(session.pointerShape(at: point(300, 200), on: left) == .openHand)

        session.click(at: point(200, 150))
        #expect(session.selectedID == rectangle.id)
        // The handles of the selected Rectangle show the direction of the size change.
        #expect(session.pointerShape(at: point(300, 200), on: left) == .resize(.bottomRight))
        #expect(session.pointerShape(at: point(100, 100), on: left) == .resize(.topLeft))
        #expect(session.pointerShape(at: point(200, 100), on: left) == .resize(.top))
        #expect(session.pointerShape(at: point(100, 150), on: left) == .resize(.left))
        #expect(session.pointerShape(at: point(100, 125), on: left) == .openHand)
        // The closed hand while the mark moves, and the handle while it changes its size.
        session.pointerDown(at: point(100, 125), on: left)
        #expect(session.pointerShape(at: point(100, 125), on: left) == .closedHand)
        session.pointerUp(at: point(100, 125))
        session.pointerDown(at: point(300, 200), on: left)
        #expect(session.pointerShape(at: point(700, 500), on: left) == .resize(.bottomRight))
        session.pointerUp(at: point(300, 200))

        // An end of the selected Arrow shows the crosshair.
        session.click(at: point(200, 300))
        #expect(session.pointerShape(at: point(300, 300), on: left) == .crosshair)
        #expect(session.pointerShape(at: point(200, 300), on: left) == .openHand)

        // The overlay view has the shape as its pointer, with no window on the screen.
        let stage = OverlayViewTests.Stage()
        stage.session.selectTool(.rectangle)
        try stage.drag(from: point(90, 80), to: point(200, 140))
        stage.session.selectTool(.select)
        stage.view.mouseMoved(with: try stage.mouse(.mouseMoved, 300, 250))
        #expect(stage.view.cursor === NSCursor.arrow)
        stage.view.mouseMoved(with: try stage.mouse(.mouseMoved, 90, 110))
        #expect(stage.view.cursor === NSCursor.openHand)
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, 90, 100))
        #expect(stage.view.cursor === NSCursor.closedHand)
        stage.view.mouseUp(with: try stage.mouse(.leftMouseUp, 90, 100))
        #expect(stage.view.cursor === NSCursor.openHand)
        stage.session.selectTool(.pen)
        #expect(stage.view.cursor === NSCursor.crosshair)
    }
}

extension DrawSession {
    /// Draws one mark with a tool, as a drag through `points`. The tool stays selected.
    @discardableResult
    func draw(_ tool: Tool, _ points: [CGPoint], on displayID: CGDirectDisplayID = Screens.left.id) -> PlacedMark {
        selectTool(tool)
        drag(points, on: displayID)
        return marks(on: displayID).last!
    }
}

extension OverlayViewTests.Stage {
    /// A mouse event with a click count and modifier keys, at a point with a top-left origin.
    func mouse(
        _ type: NSEvent.EventType, at place: CGPoint, clickCount: Int = 1, flags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: place.x, y: view.bounds.height - place.y),
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ))
    }

    /// Two clicks at one place, as AppKit sends a double-click: the second pointer down has the count 2.
    func doubleClick(at place: CGPoint) throws {
        for count in [1, 2] {
            view.mouseDown(with: try mouse(.leftMouseDown, at: place, clickCount: count))
            view.mouseUp(with: try mouse(.leftMouseUp, at: place, clickCount: count))
        }
    }
}
