import CoreGraphics
@testable import ScreendrawKit
import Testing

/// The pen and the tools, in the state machine with no window: the drawing rows of YAZ-2789
/// (1.x) and the rows of YAZ-2790 (2.x). The row number is in each test name.
@Suite struct DrawSessionTests {
    // MARK: YAZ-2789, the pen

    @Test func row1_3_theDrawHotkeyTurnsDrawingOnWithTheCrosshair() {
        let fixture = Fixture(isOn: false)
        let session = fixture.session
        var changes = 0
        session.onChange = { changes += 1 }
        #expect(session.mode == .off && session.displays.isEmpty)

        session.start(displays: [Screens.left, Screens.right])
        #expect(session.mode == .drawing)
        #expect(session.displays == [Screens.left, Screens.right])
        #expect(session.pointerShape(at: .zero, on: Screens.left.id) == .crosshair)
        #expect(changes == 1)
    }

    @Test func row1_4_aDragWithThePenMakesALineThatFollowsThePointer() {
        let session = Fixture().session
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(110, 105))
        session.pointerDragged(to: point(130, 120))
        // The line shows during the drag, before it is a finished mark.
        #expect(session.draft(on: Screens.left.id)?.points == [point(100, 100), point(110, 105), point(130, 120)])
        #expect(session.draft(on: Screens.right.id) == nil)
        #expect(session.markCount == 0)

        session.pointerUp(at: point(150, 140))
        let placed = session.marks(on: Screens.left.id)
        #expect(placed.count == 1)
        #expect(placed[0].mark.tool == .pen)
        #expect(placed[0].mark.points == [point(100, 100), point(110, 105), point(130, 120), point(150, 140)])
        #expect(session.draft(on: Screens.left.id) == nil)
    }

    @Test func row1_5_aPenClickWithNoMoveMakesOneDot() {
        let session = Fixture().session
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        // The dot shows at the pointer down.
        #expect(session.draft(on: Screens.left.id)?.points == [point(100, 100)])
        session.pointerUp(at: point(100, 100))
        #expect(session.allMarks.map { $0.mark.points } == [[point(100, 100)]])
    }

    @Test func row1_6_aDragToADifferentScreenStaysOnItsScreenAndStopsAtTheEdge() {
        let session = Fixture().session
        // The left screen is 800 by 600. The pointer goes 300 points past its right edge and
        // 50 points past its bottom edge. The Thick pen is 7 points wide.
        session.drag([point(700, 500), point(790, 550), point(1100, 650)])
        #expect(session.marks(on: Screens.right.id).isEmpty)
        let line = session.marks(on: Screens.left.id)[0].mark
        // The line stops half a line width before the edge, so the full line is visible.
        #expect(line.points == [point(700, 500), point(790, 550), point(796.5, 596.5)])

        // The same at the left and the top edge.
        session.drag([point(10, 10), point(-40, -40)])
        #expect(session.marks(on: Screens.left.id)[1].mark.points.last == point(3.5, 3.5))
    }

    @Test func row1_6_aDragOnTheSecondScreenIsAMarkOfTheSecondScreen() {
        let session = Fixture().session
        session.drag([point(10, 10), point(50, 50)], on: Screens.right.id)
        #expect(session.marks(on: Screens.left.id).isEmpty)
        #expect(session.marks(on: Screens.right.id).count == 1)
        // A pointer down on a screen that the session does not know does nothing.
        session.drag([point(10, 10), point(50, 50)], on: 99)
        #expect(session.markCount == 1)
    }

    @Test func row1_7_theDrawHotkeyTurnsDrawingOffAndNoTimerIsNeeded() {
        let session = Fixture().session
        session.setStay(.fade)
        session.drawLine()
        #expect(session.hasTimedMarks)

        session.stop()
        #expect(session.mode == .off)
        #expect(session.displays.isEmpty)
        #expect(!session.hasTimedMarks)
        // With the mode off, the pointer draws nothing.
        session.drawLine()
        #expect(session.markCount == 0)
    }

    @Test func row1_11_aRemovedMonitorDropsItsMarksAndTheOtherMarksStay() {
        let session = Fixture().session
        session.drawLine(on: Screens.left.id)
        session.drawLine(on: Screens.right.id)
        let revision = session.marksRevision

        session.setDisplays([Screens.left])
        #expect(session.displays == [Screens.left])
        #expect(session.marks(on: Screens.left.id).count == 1)
        #expect(session.marks(on: Screens.right.id).isEmpty)
        #expect(session.marksRevision > revision)
        // Undo does not bring back the mark of the removed screen. It takes back the mark of the left screen.
        session.undo()
        #expect(session.markCount == 0)
        #expect(!session.canUndo)
        session.redo()
        #expect(session.marks(on: Screens.left.id).count == 1)

        // The monitor is connected again: it has an overlay and no marks. The other marks stay.
        session.setDisplays([Screens.left, Screens.right])
        #expect(session.marks(on: Screens.left.id).count == 1)
        #expect(session.marks(on: Screens.right.id).isEmpty)
        session.drawLine(on: Screens.right.id)
        #expect(session.marks(on: Screens.right.id).count == 1)
    }

    @Test func row1_11_aRemovedMonitorDuringADragDropsTheMarkInProgress() {
        let session = Fixture().session
        session.pointerDown(at: point(10, 10), on: Screens.right.id)
        session.pointerDragged(to: point(60, 60))
        session.setDisplays([Screens.left])
        #expect(session.markCount == 0)
        #expect(session.draft(on: Screens.right.id) == nil)
        // The pointer up of that drag arrives late. It does nothing.
        session.pointerUp(at: point(70, 70))
        #expect(session.markCount == 0)
    }

    @Test func row1_11_aSetOfScreensWithNoChangeDoesNothing() {
        let session = Fixture().session
        var changes = 0
        session.onChange = { changes += 1 }
        session.setDisplays([Screens.left, Screens.right])
        #expect(changes == 0)
    }

    @Test func row1_12_aNewPointChangesOnlyTheLineInProgress() {
        let session = Fixture().session
        session.drawLine(row: 0)
        session.drawLine(row: 1)
        let finished = session.marksRevision
        let draftBefore = session.draftRevision

        session.pointerDown(at: point(10, 300), on: Screens.left.id)
        for step in 1...500 {
            session.pointerDragged(to: point(CGFloat(10 + step), 300))
        }
        // 500 points changed the line in progress 501 times, and the finished marks not one time.
        #expect(session.marksRevision == finished)
        #expect(session.draftRevision == draftBefore + 501)
        #expect(session.draft(on: Screens.left.id)?.points.count == 501)
    }

    // MARK: YAZ-2790, the tools

    @Test func row2_2_theFirstStartHasThePenThickAndRed() {
        let session = Fixture().session
        #expect(session.tool == .pen)
        #expect(session.style == MarkStyle(color: .red, size: .thick))
        #expect(Tool.allCases == [.select, .pen, .highlight, .line, .arrow, .rectangle, .ellipse, .text, .stamp])
        #expect(MarkSize.allCases == [.thin, .medium, .thick])
        #expect(MarkColor.allCases == [.red, .amber, .green, .blue, .black, .white])
    }

    @Test func row2_3_aLaterStartRemembersTheToolTheSizeAndTheColour() {
        let fixture = Fixture()
        fixture.session.selectTool(.arrow)
        fixture.session.setSize(.thin)
        fixture.session.setColor(.blue)

        let next = fixture.nextStart()
        #expect(next.tool == .arrow)
        #expect(next.style == MarkStyle(color: .blue, size: .thin))
    }

    @Test func row2_3_aBrokenSavedValueGivesTheValueOfTheFirstStart() {
        let fixture = Fixture()
        fixture.store.set("crayon", forKey: "drawTool")
        fixture.store.set(7, forKey: "drawSize")
        fixture.store.set("", forKey: "drawColor")
        fixture.store.set("forever", forKey: "drawStayMode")
        let next = fixture.nextStart()
        #expect(next.tool == .pen && next.style == MarkStyle(color: .red, size: .thick) && next.stay == .sticky)
    }

    @Test func row2_4_and2_5_penAndHighlightAreFreehandLinesAndHighlightIsWide() {
        let session = Fixture().session
        let path = [point(50, 50), point(60, 70), point(90, 80)]
        session.drag(path)
        session.selectTool(.highlight)
        session.drag(path)

        let marks = session.allMarks.map { $0.mark }
        #expect(marks.map { $0.tool } == [.pen, .highlight])
        #expect(marks[0].points == path && marks[1].points == path)
        // Thick: the Pen is 7 points and Highlight is 24 points.
        #expect(marks[0].style.lineWidth(for: .pen) == 7)
        #expect(marks[1].style.lineWidth(for: .highlight) == 24)
        for size in MarkSize.allCases {
            let style = MarkStyle(color: .red, size: size)
            #expect(style.lineWidth(for: .highlight) > 2 * style.lineWidth(for: .pen))
        }
    }

    @Test func row2_5_aHighlightClickWithNoMoveMakesNoMark() {
        let session = Fixture().session
        session.selectTool(.highlight)
        // A Highlight line has flat ends, so a line with no length shows nothing.
        session.click(at: point(100, 100))
        #expect(session.markCount == 0)
        #expect(!session.canUndo)
    }

    @Test func row2_6_and2_7_arrowRectangleAndEllipseKeepTheStartAndTheEndOfTheDrag() {
        let session = Fixture().session
        for tool in [Tool.arrow, .rectangle, .ellipse] {
            session.selectTool(tool)
            session.drag([point(100, 100), point(150, 120), point(200, 180)])
        }
        let marks = session.allMarks.map { $0.mark }
        #expect(marks.map { $0.tool } == [.arrow, .rectangle, .ellipse])
        for mark in marks {
            #expect(mark.points == [point(100, 100), point(200, 180)])
        }
    }

    @Test func row2_8_aClickOpensATextAndEnterFinishesIt() {
        let session = Fixture().session
        session.selectTool(.text)
        #expect(session.pointerShape(at: .zero, on: Screens.left.id) == .iBeam)
        session.click(at: point(200, 150))
        // The click is the middle of the first line. Thick is 24 points, so a line is 30 points.
        let edit = session.textEdit
        #expect(edit?.displayID == Screens.left.id)
        #expect(edit?.origin == point(200, 135))
        #expect(edit?.wrapWidth == 600)
        #expect(edit?.style == MarkStyle(color: .red, size: .thick))
        #expect(session.markCount == 0)

        session.textChanged("Look here")
        session.completeText()
        #expect(session.textEdit == nil)
        let mark = session.allMarks[0].mark
        #expect(mark.tool == .text && mark.text == "Look here")
        #expect(mark.points == [point(200, 135)] && mark.wrapWidth == 600)
    }

    @Test func row2_8_aClickAtADifferentPlaceFinishesTheTextAndOpensTheNext() {
        let session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("One")
        session.click(at: point(300, 400), on: Screens.left.id)
        #expect(session.allMarks.map { $0.mark.text } == ["One"])
        #expect(session.textEdit?.origin == point(300, 385))
        #expect(session.textEdit?.text == "")
    }

    @Test func row2_8_anEmptyTextMakesNoMark() {
        let session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.completeText()
        session.click(at: point(200, 150))
        session.textChanged("  \n ")
        session.completeText()
        #expect(session.markCount == 0)
        #expect(session.textEdit == nil)
        #expect(!session.canUndo)
    }

    @Test func row2_8_aTextNearTheEdgeStaysOnTheScreen() {
        let session = Fixture().session
        session.selectTool(.text)
        // The left screen is 800 by 600.
        session.click(at: point(795, 598))
        #expect(session.textEdit?.origin == point(752, 570))
        #expect(session.textEdit?.wrapWidth == 48)
        session.click(at: point(2, 3))
        #expect(session.textEdit?.origin == point(2, 0))
    }

    @Test func row2_9_aRectangleAnEllipseOrAnArrowSmallerThan4PointsMakesNoMark() {
        let session = Fixture().session
        for tool in [Tool.rectangle, .ellipse, .arrow] {
            session.selectTool(tool)
            session.click(at: point(100, 100))
            session.drag([point(100, 100), point(103, 102)])
            #expect(session.markCount == 0, "a small \(tool.name)")
            #expect(session.draft(on: Screens.left.id) == nil)
        }
        #expect(!session.canUndo)

        // 4 points is a mark. A Rectangle can be thin: its longer side counts.
        session.selectTool(.rectangle)
        session.drag([point(100, 100), point(104, 100)])
        session.selectTool(.ellipse)
        session.drag([point(100, 100), point(101, 104)])
        session.selectTool(.arrow)
        session.drag([point(100, 100), point(103, 103)])
        #expect(session.allMarks.map { $0.mark.tool } == [.rectangle, .ellipse, .arrow])
    }

    @Test func row2_10_aChangeOfSizeOrColourAppliesToNewMarksOnly() {
        let session = Fixture().session
        session.drawLine(row: 0)
        session.setSize(.thin)
        session.setColor(.green)
        session.drawLine(row: 1)

        let styles = session.allMarks.map { $0.mark.style }
        #expect(styles == [MarkStyle(color: .red, size: .thick), MarkStyle(color: .green, size: .thin)])
    }

    @Test func row2_10_aTextThatIsOpenGetsTheNewSizeAndColour() {
        let session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Note")
        // A text that is open is not a mark yet.
        session.setColor(.blue)
        session.setSize(.medium)
        #expect(session.textEdit?.style == MarkStyle(color: .blue, size: .medium))
        session.completeText()
        #expect(session.allMarks[0].mark.style == MarkStyle(color: .blue, size: .medium))
    }

    @Test func row2_11_undoRemovesTheNewestMark() {
        let session = Fixture().session
        #expect(!session.canUndo)
        session.drawLine(row: 0)
        session.drawLine(row: 1, on: Screens.right.id)
        session.drawLine(row: 2)
        #expect(session.canUndo)

        // The newest mark goes first, on any screen.
        session.undo()
        #expect(session.marks(on: Screens.left.id).count == 1 && session.marks(on: Screens.right.id).count == 1)
        session.undo()
        #expect(session.marks(on: Screens.left.id).count == 1 && session.marks(on: Screens.right.id).isEmpty)
        session.undo()
        #expect(session.markCount == 0 && !session.canUndo)
        // One more Undo does nothing.
        session.undo()
        #expect(session.markCount == 0)
    }

    @Test func row2_12_redoBringsTheMarkBackAndANewMarkEmptiesTheRedoList() {
        let session = Fixture().session
        session.drawLine(row: 0)
        session.drawLine(row: 1)
        let both = session.allMarks.map { $0.mark }
        #expect(!session.canRedo)

        session.undo()
        session.undo()
        #expect(session.canRedo)
        session.redo()
        session.redo()
        #expect(session.allMarks.map { $0.mark } == both)
        #expect(!session.canRedo)

        session.undo()
        #expect(session.canRedo)
        session.drawLine(row: 2)
        #expect(!session.canRedo)
        session.redo()
        #expect(session.markCount == 2)
    }

    @Test func row2_13_theHistoryHolds200StepsAndTheOldestDropsFirst() {
        let session = Fixture().session
        for row in 0..<205 {
            session.drawLine(row: row % 50)
        }
        #expect(session.markCount == 205)
        for _ in 0..<300 {
            session.undo()
        }
        // 200 steps went back. The 5 oldest marks stay: their steps dropped first.
        #expect(DrawSession.historyLimit == 200)
        #expect(session.markCount == 5)
        #expect(session.allMarks.map { $0.id } == [1, 2, 3, 4, 5])
        #expect(!session.canUndo)
        for _ in 0..<300 {
            session.redo()
        }
        #expect(session.markCount == 205)
    }

    @Test func row2_14_clearAllRemovesEachMarkOnEachScreenAndOneUndoBringsThemBack() {
        let session = Fixture().session
        session.drawLine(row: 0, on: Screens.left.id)
        session.drawLine(row: 1, on: Screens.left.id)
        session.drawLine(row: 2, on: Screens.right.id)
        let left = session.marks(on: Screens.left.id).map { $0.mark }
        let right = session.marks(on: Screens.right.id).map { $0.mark }

        session.clearAll()
        #expect(session.markCount == 0)
        #expect(session.mode == .drawing)

        session.undo()
        #expect(session.marks(on: Screens.left.id).map { $0.mark } == left)
        #expect(session.marks(on: Screens.right.id).map { $0.mark } == right)
        // Redo clears again, and Undo brings the marks back again.
        session.redo()
        #expect(session.markCount == 0)
        session.undo()
        #expect(session.markCount == 3)
        // The step before the clear is the third mark.
        session.undo()
        #expect(session.marks(on: Screens.right.id).isEmpty && session.marks(on: Screens.left.id).count == 2)
    }

    @Test func row2_14_clearAllWithNoMarkMakesNoStep() {
        let session = Fixture().session
        session.clearAll()
        #expect(!session.canUndo)
        session.drawLine()
        session.undo()
        // Clear all with no mark keeps the Redo list.
        session.clearAll()
        #expect(session.canRedo)
    }

    @Test func row2_18_oneToolSizeAndColourApplyToEachScreen() {
        let session = Fixture().session
        session.selectTool(.rectangle)
        session.setSize(.medium)
        session.setColor(.amber)
        session.drag([point(10, 10), point(60, 60)], on: Screens.left.id)
        session.drag([point(10, 10), point(60, 60)], on: Screens.right.id)
        for placed in session.allMarks {
            #expect(placed.mark.tool == .rectangle)
            #expect(placed.mark.style == MarkStyle(color: .amber, size: .medium))
        }
        #expect(session.allMarks.count == 2)
    }
}
