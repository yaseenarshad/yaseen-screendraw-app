import CoreGraphics
@testable import ScreendrawKit
import Testing

/// Fade, Hold and Sticky: the rows of YAZ-2791 (3.x). Each test sets the clock. No test sleeps.
@Suite struct StayModeTests {
    private func isNear(_ value: CGFloat, _ expected: CGFloat) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test func theTimesAreTheApprovedTimes() {
        #expect(DrawSession.fadeTime == 2)
        #expect(DrawSession.holdTime == 5)
        #expect(DrawSession.fadeOutTime == 1)
        #expect(StayMode.allCases == [.fade, .hold, .sticky])
    }

    @Test func row3_1_theFirstStartIsSticky() {
        #expect(Fixture().session.stay == .sticky)
    }

    @Test func row3_2_aLaterStartRemembersTheSwitch() {
        let fixture = Fixture()
        fixture.session.setStay(.hold)
        #expect(fixture.nextStart().stay == .hold)
        fixture.session.setStay(.fade)
        #expect(fixture.nextStart().stay == .fade)
    }

    @Test func row3_3_aFadeMarkIsFullFor1SecondThenFadesFor1SecondThenIsRemoved() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.drawLine()
        let mark = session.allMarks[0]
        #expect(mark.stay == .fade)
        #expect(session.opacity(of: mark) == 1)

        clock.time += 1
        session.tick()
        #expect(session.opacity(of: mark) == 1)
        clock.time += 0.25
        #expect(isNear(session.opacity(of: mark), 0.75))
        clock.time += 0.5
        session.tick()
        #expect(isNear(session.opacity(of: mark), 0.25))
        #expect(session.markCount == 1)

        // 2 seconds after the pointer up, the mark is removed.
        clock.time += 0.25
        var changes = 0
        session.onChange = { changes += 1 }
        session.tick()
        #expect(session.markCount == 0)
        #expect(changes == 1)
        #expect(!session.hasTimedMarks)
    }

    @Test func row3_4_holdMarksFadeTogether5SecondsAfterTheLastActivity() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.hold)
        session.drawLine(row: 0)
        clock.time += 3
        session.drawLine(row: 1, on: Screens.right.id)
        let first = session.allMarks[0], second = session.allMarks[1]

        // 4.75 seconds after the second mark, the first mark is 7.75 seconds old and still at full strength.
        clock.time += 4.75
        session.tick()
        #expect(session.opacity(of: first) == 1 && session.opacity(of: second) == 1)

        // They fade together.
        clock.time += 0.75
        session.tick()
        #expect(isNear(session.opacity(of: first), 0.5) && isNear(session.opacity(of: second), 0.5))
        #expect(session.markCount == 2)

        // 6 seconds after the last activity, the two marks are removed in one change.
        clock.time += 0.5
        var changes = 0
        session.onChange = { changes += 1 }
        session.tick()
        #expect(session.markCount == 0)
        #expect(changes == 1)
    }

    @Test func row3_5_aPointerDownADragAndAPointerUpOfAnyMarkAreDrawingActivity() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.hold)
        session.drawLine()
        let hold = session.allMarks[0]
        // The next mark is a Sticky mark. Its pointer events still count for the Hold mark.
        session.setStay(.sticky)

        clock.time += 5.5
        #expect(isNear(session.opacity(of: hold), 0.5))
        session.pointerDown(at: point(300, 300), on: Screens.left.id)
        #expect(session.opacity(of: hold) == 1)

        clock.time += 5.5
        #expect(isNear(session.opacity(of: hold), 0.5))
        session.pointerDragged(to: point(320, 320))
        #expect(session.opacity(of: hold) == 1)

        clock.time += 5.5
        #expect(isNear(session.opacity(of: hold), 0.5))
        session.pointerUp(at: point(320, 320))
        #expect(session.opacity(of: hold) == 1)

        // The clicks of the toolbar are not drawing activity.
        clock.time += 5.5
        session.selectTool(.arrow)
        session.setColor(.blue)
        session.setStay(.fade)
        #expect(isNear(session.opacity(of: hold), 0.5))
        clock.time += 0.5
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.sticky])
    }

    @Test func row3_6_aStickyMarkStaysUntilClearAllOrEsc() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.drawLine()
        #expect(session.allMarks[0].stay == .sticky)
        #expect(!session.hasTimedMarks)

        clock.time += 24 * 3600
        session.tick()
        #expect(session.markCount == 1)
        #expect(session.opacity(of: session.allMarks[0]) == 1)

        session.clearAll()
        #expect(session.markCount == 0)
        session.undo()
        #expect(session.markCount == 1)
        session.escape()
        #expect(session.markCount == 0)
    }

    @Test func row3_7_aChangeOfTheSwitchAppliesToNewMarksOnly() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.drawLine(row: 0)
        session.setStay(.fade)
        session.drawLine(row: 1)
        session.setStay(.hold)
        session.drawLine(row: 2)
        session.setStay(.sticky)
        #expect(session.allMarks.map { $0.stay } == [.sticky, .fade, .hold])

        // Each mark keeps its value: the Fade mark goes at 2 seconds, the Hold mark at 6, the Sticky mark stays.
        clock.time += 2
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.sticky, .hold])
        clock.time += 4
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.sticky])
    }

    @Test func row3_8_aMarkInProgressDoesNotFadeAndItsClockStartsWhenItIsFinished() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(150, 150))
        // The user holds the pointer down for 10 seconds.
        clock.time += 10
        session.tick()
        #expect(session.draft(on: Screens.left.id)?.points.count == 2)
        #expect(!session.hasTimedMarks)

        session.pointerUp(at: point(200, 200))
        let mark = session.allMarks[0]
        #expect(mark.shownAt == clock.time)
        #expect(session.opacity(of: mark) == 1)
        clock.time += 1.75
        session.tick()
        #expect(session.markCount == 1)
        clock.time += 0.25
        session.tick()
        #expect(session.markCount == 0)
    }

    @Test func row3_9_theClockOfAFadeTextStartsWhenTheTextIsFinished() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.selectTool(.text)
        session.click(at: point(200, 150))
        // The user types for 10 seconds.
        clock.time += 10
        session.tick()
        session.textChanged("Slow typing")
        #expect(session.textEdit != nil)

        session.completeText()
        let text = session.allMarks[0]
        #expect(text.stay == .fade && text.shownAt == clock.time)
        #expect(session.opacity(of: text) == 1)
        clock.time += 1.5
        #expect(isNear(session.opacity(of: text), 0.5))
        clock.time += 0.5
        session.tick()
        #expect(session.markCount == 0)
    }

    @Test func row3_9_theClockOfAHoldTextStartsWhenTheTextIsFinished() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.hold)
        session.selectTool(.text)
        session.click(at: point(200, 150))
        clock.time += 10
        session.textChanged("Slow typing")
        session.completeText()

        let text = session.allMarks[0]
        #expect(text.stay == .hold)
        #expect(session.opacity(of: text) == 1)
        clock.time += 5
        session.tick()
        #expect(session.opacity(of: text) == 1 && session.markCount == 1)
        clock.time += 1
        session.tick()
        #expect(session.markCount == 0)
    }

    @Test func row3_10_undoGoesToTheNewestMarkThatStillExists() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.drawLine(row: 0)
        session.setStay(.fade)
        session.drawLine(row: 1)
        clock.time += 2
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.sticky])

        // The Fade mark is gone. Undo takes back the Sticky mark, not nothing.
        session.undo()
        #expect(session.markCount == 0)
        #expect(!session.canUndo)
        // Redo brings back the Sticky mark only. The removed Fade mark does not come back.
        session.redo()
        #expect(session.allMarks.map { $0.stay } == [.sticky])
        #expect(!session.canRedo)
    }

    @Test func row3_10_holdMarksThatTheirClockRemovedDoNotComeBack() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.hold)
        session.drawLine(row: 0)
        session.drawLine(row: 1)
        clock.time += 6
        session.tick()
        #expect(session.markCount == 0)
        #expect(!session.canUndo && !session.canRedo)
    }

    @Test func row3_11_undoOfClearAllStartsTheClocksAgain() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.drawLine(row: 0)
        session.setStay(.hold)
        session.drawLine(row: 1)
        clock.time += 0.5
        session.clearAll()
        #expect(session.markCount == 0 && !session.hasTimedMarks)

        // A long time later, Undo brings the two marks back at full strength.
        clock.time += 60
        session.tick()
        session.undo()
        #expect(session.allMarks.map { $0.stay } == [.fade, .hold])
        #expect(session.hasTimedMarks)
        for mark in session.allMarks {
            #expect(session.opacity(of: mark) == 1)
        }
        // The Fade mark is removed 2 seconds after the Undo, and the Hold mark 6 seconds after it.
        clock.time += 1.75
        session.tick()
        #expect(session.markCount == 2)
        clock.time += 0.25
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.hold])
        clock.time += 3.75
        session.tick()
        #expect(session.markCount == 1)
        clock.time += 0.25
        session.tick()
        #expect(session.markCount == 0)
    }

    @Test func row3_11_redoStartsTheClockAgain() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.drawLine()
        clock.time += 1.5
        session.undo()
        #expect(session.markCount == 0)

        clock.time += 30
        session.redo()
        let mark = session.allMarks[0]
        #expect(mark.shownAt == clock.time)
        #expect(session.opacity(of: mark) == 1)
        clock.time += 1.75
        session.tick()
        #expect(session.markCount == 1)
        clock.time += 0.25
        session.tick()
        #expect(session.markCount == 0)
        // The clock removed the mark, so Undo has no step for it.
        #expect(!session.canUndo)
    }

    @Test func row3_12_theClocksContinueInClickThrough() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        session.setStay(.fade)
        session.drawLine(row: 0)
        session.setStay(.hold)
        session.drawLine(row: 1)
        session.toggleClickThrough()
        #expect(session.mode == .clickThrough)
        #expect(session.hasTimedMarks)

        clock.time += 1.5
        #expect(isNear(session.opacity(of: session.allMarks[0]), 0.5))
        clock.time += 0.5
        session.tick()
        #expect(session.allMarks.map { $0.stay } == [.hold])
        clock.time += 4
        session.tick()
        #expect(session.markCount == 0)
        #expect(session.mode == .clickThrough)
    }

    @Test func row3_13_noTimerIsNeededWhenNoFadeOrHoldMarkExists() {
        let fixture = Fixture()
        let session = fixture.session, clock = fixture.clock
        #expect(!session.hasTimedMarks)
        session.drawLine(row: 0)
        #expect(!session.hasTimedMarks)

        session.setStay(.fade)
        // The switch alone needs no timer. A mark in progress needs no timer.
        #expect(!session.hasTimedMarks)
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        #expect(!session.hasTimedMarks)
        session.pointerUp(at: point(150, 150))
        #expect(session.hasTimedMarks)

        // Undo removes the last Fade mark: no timer is needed.
        session.undo()
        #expect(!session.hasTimedMarks)
        session.redo()
        #expect(session.hasTimedMarks)
        session.clearAll()
        #expect(!session.hasTimedMarks)
        session.undo()
        #expect(session.hasTimedMarks)
        clock.time += 2
        session.tick()
        #expect(!session.hasTimedMarks)
        // A tick with no Fade or Hold mark changes nothing.
        var changes = 0
        session.onChange = { changes += 1 }
        session.tick()
        #expect(changes == 0 && session.markCount == 1)
    }
}
