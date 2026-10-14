import CoreGraphics
@testable import ScreendrawKit
import Testing

/// Click-through and the marks that come back: the rows of YAZ-2792 (4.x), in the state
/// machine with no window. `DrawControllerTests` has the window side of the same rows.
/// Esc pauses the pen now (D20): `EscPausesTests` has rows 4.30 to 4.45, which replace rows 4.8 to 4.10.
@Suite struct ModeTests {
    @Test func row4_1_theClickThroughHotkeyKeepsTheMarksAndThePointerDrawsNothing() {
        let session = Fixture().session
        session.drawLine(on: Screens.left.id)
        session.drawLine(on: Screens.right.id)
        var changes = 0
        session.onChange = { changes += 1 }

        session.toggleClickThrough()
        #expect(session.mode == .clickThrough)
        #expect(session.markCount == 2)
        #expect(changes == 1)
        // The overlay ignores the mouse in this mode. A pointer event that still arrives draws nothing.
        session.drawLine(row: 3)
        #expect(session.markCount == 2)
        #expect(session.draft(on: Screens.left.id) == nil)
    }

    @Test func row4_2_aClickOnAToolInClickThroughGoesBackToDrawingWithThatTool() {
        let session = Fixture().session
        session.toggleClickThrough()
        session.selectTool(.ellipse)
        #expect(session.mode == .drawing)
        #expect(session.tool == .ellipse)
        session.drag([point(10, 10), point(80, 60)])
        #expect(session.allMarks.map { $0.mark.tool } == [.ellipse])
    }

    @Test func row4_2_clearAllAndCloseDoTheirWorkInClickThrough() {
        let session = Fixture().session
        session.drawLine()
        session.toggleClickThrough()

        session.clearAll()
        #expect(session.markCount == 0)
        #expect(session.mode == .clickThrough)
        // Undo and the size, colour and stay buttons also work, and the mode stays.
        session.undo()
        session.setSize(.thin)
        session.setColor(.white)
        session.setStay(.hold)
        #expect(session.markCount == 1 && session.mode == .clickThrough)

        session.stop()
        #expect(session.mode == .off)
    }

    @Test func row4_3_theClickThroughHotkeyGoesBackToDrawing() {
        let session = Fixture().session
        session.toggleClickThrough()
        session.toggleClickThrough()
        #expect(session.mode == .drawing)
        session.drawLine()
        #expect(session.markCount == 1)
    }

    @Test func row4_4_theClickThroughHotkeyDoesNothingWhenTheModeIsOff() {
        let session = Fixture(isOn: false).session
        var changes = 0
        session.onChange = { changes += 1 }
        session.toggleClickThrough()
        #expect(session.mode == .off)
        #expect(changes == 0)
    }

    @Test func row4_5_theDrawHotkeyKeepsTheStickyMarksAndDropsTheFadeAndHoldMarks() {
        for clickThroughFirst in [false, true] {
            let session = Fixture().session
            session.drawLine(row: 0)
            session.setStay(.fade)
            session.drawLine(row: 1)
            session.setStay(.hold)
            session.drawLine(row: 2, on: Screens.right.id)
            session.setStay(.sticky)
            session.drawLine(row: 3, on: Screens.right.id)
            if clickThroughFirst { session.toggleClickThrough() }

            session.stop()
            #expect(session.mode == .off)
            #expect(session.marks(on: Screens.left.id).map { $0.stay } == [.sticky])
            #expect(session.marks(on: Screens.right.id).map { $0.stay } == [.sticky])
            #expect(!session.hasTimedMarks)
        }
    }

    @Test func row4_6_theKeptMarksShowAgainAtTheSamePlacesOnTheSameScreens() {
        let session = Fixture().session
        session.drawLine(row: 0, on: Screens.left.id)
        session.selectTool(.rectangle)
        session.drag([point(30, 40), point(130, 90)], on: Screens.right.id)
        let left = session.marks(on: Screens.left.id)
        let right = session.marks(on: Screens.right.id)
        session.stop()

        session.start(displays: [Screens.left, Screens.right])
        #expect(session.mode == .drawing)
        #expect(session.marks(on: Screens.left.id) == left)
        #expect(session.marks(on: Screens.right.id) == right)
        // Undo still knows the two marks.
        session.undo()
        #expect(session.marks(on: Screens.right.id).isEmpty && session.marks(on: Screens.left.id) == left)
    }

    @Test func row4_6_theMarksOfAScreenThatIsGoneAreDropped() {
        let session = Fixture().session
        session.drawLine(on: Screens.left.id)
        session.drawLine(on: Screens.right.id)
        session.stop()
        // The session keeps the marks of the two screens while the mode is off.
        #expect(session.markCount == 2)

        // The right monitor was removed while drawing was off.
        session.start(displays: [Screens.left])
        #expect(session.marks(on: Screens.left.id).count == 1)
        #expect(session.marks(on: Screens.right.id).isEmpty)
        #expect(session.markCount == 1)
        session.undo()
        #expect(session.markCount == 0 && !session.canUndo)
    }

    @Test func row4_7_escWithAnOpenTextCancelsOnlyTheText() {
        let session = Fixture().session
        session.drawLine()
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Not wanted")

        session.escape()
        #expect(session.textEdit == nil)
        #expect(session.mode == .drawing)
        #expect(session.allMarks.map { $0.mark.tool } == [.pen])
    }

    @Test func row4_11_aHotkeyDuringADragFinishesTheMarkFirst() {
        // The click-through hotkey.
        var session = Fixture().session
        var log: [String] = []
        session.onChange = { [unowned session] in log.append("\(session.mode) \(session.markCount)") }
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(160, 140))
        log = []
        session.toggleClickThrough()
        #expect(log == ["drawing 1", "clickThrough 1"])
        #expect(session.allMarks[0].mark.points == [point(100, 100), point(160, 140)])
        #expect(session.draft(on: Screens.left.id) == nil)
        // The rest of that drag arrives late. It draws nothing.
        session.pointerDragged(to: point(200, 200))
        session.pointerUp(at: point(200, 200))
        #expect(session.markCount == 1 && session.allMarks[0].mark.points.count == 2)

        // The draw hotkey.
        session = Fixture().session
        log = []
        session.onChange = { [unowned session] in log.append("\(session.mode) \(session.markCount)") }
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(160, 140))
        log = []
        session.stop()
        #expect(log == ["drawing 1", "off 1"])
        #expect(session.markCount == 1)
    }

    @Test func row4_11_aSmallShapeInProgressIsDroppedByAHotkey() {
        let session = Fixture().session
        session.selectTool(.rectangle)
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(102, 101))
        session.toggleClickThrough()
        #expect(session.mode == .clickThrough && session.markCount == 0)
    }

    @Test func row4_12_aHotkeyWhileATextIsOpenFinishesTheTextFirst() {
        // The click-through hotkey keeps a text that is not empty.
        var session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Kept")
        session.toggleClickThrough()
        #expect(session.mode == .clickThrough)
        #expect(session.textEdit == nil)
        #expect(session.allMarks.map { $0.mark.text } == ["Kept"])

        // The draw hotkey keeps it too. The text is a Sticky mark, so it stays in memory.
        session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Kept")
        session.stop()
        #expect(session.mode == .off && session.textEdit == nil)
        #expect(session.allMarks.map { $0.mark.text } == ["Kept"])

        // An empty text makes no mark.
        session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.toggleClickThrough()
        #expect(session.mode == .clickThrough && session.textEdit == nil && session.markCount == 0)
    }

    @Test func row4_13_noMarkIsWrittenToTheDisk() {
        let fixture = Fixture()
        let session = fixture.session
        session.selectTool(.highlight)
        session.setSize(.medium)
        session.setColor(.green)
        session.setStay(.hold)
        session.drawLine()
        session.setStay(.sticky)
        session.drawLine(row: 1)
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Secret")
        session.completeText()
        session.clearAll()
        session.undo()
        session.stop()

        // The settings hold four small values, and no other key.
        let saved = fixture.store.values
        #expect(Set(saved.keys) == ["drawTool", "drawSize", "drawColor", "drawStayMode"])
        #expect(saved["drawTool"] as? String == "text")
        #expect(saved["drawSize"] as? String == "medium")
        #expect(saved["drawColor"] as? String == "green")
        #expect(saved["drawStayMode"] as? String == "sticky")

        // After Quit, the next start of the app has no mark and no history.
        let next = fixture.nextStart()
        next.start(displays: [Screens.left, Screens.right])
        #expect(next.markCount == 0)
        #expect(!next.canUndo && !next.canRedo)
    }

    @Test func row4_14_theKeptMarksAreDataOnlyWhileTheModeIsOff() {
        let fixture = Fixture()
        let session = fixture.session
        session.drawLine()
        session.setStay(.fade)
        session.drawLine(row: 1)
        session.stop()

        // No screen, no mark in progress, and no Fade or Hold mark: nothing needs a timer.
        #expect(session.displays.isEmpty)
        #expect(!session.hasTimedMarks)
        #expect(session.markCount == 1)
        var changes = 0
        session.onChange = { changes += 1 }
        fixture.clock.time += 3600
        session.tick()
        session.pointerDown(at: point(10, 10), on: Screens.left.id)
        session.pointerDragged(to: point(50, 50))
        session.pointerUp(at: point(50, 50))
        session.escape()
        session.toggleClickThrough()
        #expect(changes == 0)
        #expect(session.markCount == 1 && session.mode == .off)
    }

    @Test func clearAllFromTheMenuWorksWhileTheModeIsOffAndOneUndoBringsTheMarksBack() {
        let session = Fixture().session
        session.drawLine()
        session.stop()
        // The menu row "Clear all" (`DrawControlling.clearAll`).
        session.clearAll()
        #expect(session.markCount == 0)
        session.start(displays: [Screens.left, Screens.right])
        session.undo()
        #expect(session.markCount == 1)
    }
}
