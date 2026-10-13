import AppKit
@testable import ScreendrawKit
import Testing

/// The controller and its windows, out of sight. The controller gets fixed screens, a fixed
/// pointer and `showsWindows: false`: the windows are made, but no call puts one on a screen.
/// These tests have the window side of the rows, and the full flow through `DrawControlling`.
@MainActor @Suite struct DrawControllerTests {
    /// The screens and the pointer that the controller sees. A test changes them.
    final class Desk {
        var screens = [Screens.leftScreen, Screens.rightScreen]
        /// On the left screen.
        var pointer = CGPoint(x: 400, y: 300)
    }

    @MainActor final class Stage {
        let clock = TestClock()
        let store = TestDefaults()
        let desk = Desk()
        let controller: DrawController
        var modes: [DrawMode] = []

        init() {
            controller = DrawController(
                defaults: store.defaults,
                now: { [clock] in clock.time },
                screens: { [desk] in desk.screens },
                pointer: { [desk] in desk.pointer },
                showsWindows: false
            )
            controller.onModeChange = { [unowned self] in self.modes.append($0) }
        }

        var session: DrawSession { controller.session }

        /// A click on a button of the toolbar: its action, as AppKit sends it.
        func press(_ name: String) throws {
            let button = try #require(controller.toolbarPanel?.toolbarView.button(named: name))
            #expect(button.isEnabled, "the button \(name) is not enabled")
            // The action goes through the app object. It is an accessory app: no Dock icon, no window.
            NSApplication.shared.setActivationPolicy(.accessory)
            #expect(button.sendAction(button.action, to: button.target))
        }

        /// No window of the controller is on a screen.
        var nothingIsOnAScreen: Bool {
            let windows: [NSWindow] = controller.overlays + (controller.toolbarPanel.map { [$0] } ?? [])
            return windows.allSatisfy { !$0.isVisible }
        }
    }

    // MARK: YAZ-2789

    @Test func row1_3_theDrawHotkeyMakesOneOverlayForEachScreenAndTheToolbar() {
        let stage = Stage()
        let controller = stage.controller
        #expect(controller.mode == .off)
        #expect(controller.overlays.isEmpty && controller.toolbarPanel == nil)

        controller.toggleDrawing()
        #expect(controller.mode == .drawing)
        #expect(stage.modes == [.drawing])
        #expect(controller.overlays.map { $0.frame } == [Screens.leftScreen.frame, Screens.rightScreen.frame])
        #expect(controller.overlays.map { $0.overlayView.frame.size } == [Screens.left.size, Screens.right.size])
        #expect(controller.toolbarPanel != nil)
        #expect(stage.session.pointerShape == .crosshair)
        #expect(stage.nothingIsOnAScreen)
    }

    @Test func row1_7_theDrawHotkeyClosesTheWindowsAndNoTimerRuns() {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.setStay(.fade)
        stage.session.drawLine()
        #expect(controller.timer != nil)
        #expect(controller.screenObserver != nil)

        controller.toggleDrawing()
        #expect(controller.mode == .off)
        #expect(stage.modes == [.drawing, .off])
        #expect(controller.overlays.isEmpty)
        #expect(controller.toolbarPanel == nil)
        #expect(controller.timer == nil)
        #expect(controller.screenObserver == nil)
    }

    @Test func row1_8_and1_9_theOverlayIsATransparentPanelOneLevelBelowTheScreenSaver() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        for overlay in stage.controller.overlays {
            // Transparent, with no border and no shadow: only the marks show.
            #expect(!overlay.isOpaque && overlay.backgroundColor == .clear && !overlay.hasShadow)
            #expect(overlay.styleMask.contains(.nonactivatingPanel) && !overlay.styleMask.contains(.titled))
            // Above a full-screen app, the menu bar and the Dock, on every Space (row 1.8).
            #expect(overlay.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]))
            #expect(!overlay.hidesOnDeactivate)
            #expect(overlay.level.rawValue > Int(CGWindowLevelForKey(.mainMenuWindow)))
            #expect(overlay.level.rawValue > Int(CGWindowLevelForKey(.dockWindow)))
            // One below the freeze of Yaseen Screenshot, which is at `.screenSaver` (row 1.9).
            #expect(overlay.level.rawValue == NSWindow.Level.screenSaver.rawValue - 1)
            // A screenshot shows the marks: the overlay does not ask to be left out.
            #expect(overlay.sharingType != .none)
            #expect(!overlay.isReleasedWhenClosed)
        }
    }

    @Test func row1_10_theOverlayTakesTheKeyboardInModeDrawing() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        let overlay = try #require(stage.controller.overlays.first)
        #expect(overlay.canBecomeKey && !overlay.becomesKeyOnlyIfNeeded)
        #expect(!overlay.ignoresMouseEvents)
        #expect(overlay.contentView === overlay.overlayView)
        #expect(overlay.firstResponder === overlay.overlayView)
        #expect(overlay.overlayView.acceptsFirstResponder)
    }

    @Test func row1_11_aChangeOfTheScreensMakesTheOverlaysAgain() throws {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.drawLine(on: Screens.right.id)
        let oldOverlays = controller.overlays
        let panel = try #require(controller.toolbarPanel)
        let toolbarOrigin = panel.frame.origin

        // The right monitor is removed.
        stage.desk.screens = [Screens.leftScreen]
        controller.screensChanged()
        #expect(controller.mode == .drawing)
        #expect(controller.overlays.map { $0.frame } == [Screens.leftScreen.frame])
        #expect(controller.overlays.allSatisfy { new in !oldOverlays.contains { $0 === new } })
        #expect(stage.session.marks(on: Screens.left.id).count == 1)
        #expect(stage.session.marks(on: Screens.right.id).isEmpty)
        // The new overlay shows the mark that stays.
        #expect(controller.overlays[0].overlayView.markLayers.count == 1)
        // The toolbar is on the left screen, so it stays where it is.
        #expect(controller.toolbarPanel === panel && panel.frame.origin == toolbarOrigin)
        #expect(stage.nothingIsOnAScreen)

        // The monitor is connected again, in click-through: the new overlays ignore the mouse too.
        controller.toggleClickThrough()
        stage.desk.screens = [Screens.leftScreen, Screens.rightScreen]
        controller.screensChanged()
        #expect(controller.overlays.count == 2)
        #expect(controller.overlays.allSatisfy { $0.ignoresMouseEvents })
        #expect(stage.session.markCount == 1)
    }

    @Test func row1_11_theToolbarMovesWhenItsScreenIsGone() throws {
        let stage = Stage()
        // The pointer is on the right screen, so the toolbar starts there.
        stage.desk.pointer = CGPoint(x: 1000, y: 100)
        stage.controller.toggleDrawing()
        let panel = try #require(stage.controller.toolbarPanel)
        #expect(Screens.rightScreen.frame.contains(CGPoint(x: panel.frame.midX, y: panel.frame.midY)))

        stage.desk.screens = [Screens.leftScreen]
        stage.controller.screensChanged()
        #expect(panel.frame.origin == Toolbar.origin(for: panel.frame.size, on: Screens.leftScreen.visibleFrame))
    }

    @Test func row1_11_noChangeOfTheScreensKeepsTheOverlays() {
        let stage = Stage()
        stage.controller.toggleDrawing()
        let overlays = stage.controller.overlays
        stage.controller.screensChanged()
        #expect(stage.controller.overlays.elementsEqual(overlays) { $0 === $1 })
        // With the mode off, a change of the screens does nothing.
        stage.controller.toggleDrawing()
        stage.desk.screens = [Screens.leftScreen]
        stage.controller.screensChanged()
        #expect(stage.controller.overlays.isEmpty)
    }

    // MARK: YAZ-2790

    @Test func row2_1_theToolbarShowsAtTheBottomCentreOfTheScreenThatHasThePointer() throws {
        // The pure rule: the centre of the screen, 24 points above the Dock.
        let origin = Toolbar.origin(
            for: CGSize(width: 300, height: 72), on: CGRect(x: 100, y: 50, width: 800, height: 500)
        )
        #expect(origin == CGPoint(x: 350, y: 74))

        // The pointer is on the left screen.
        var stage = Stage()
        stage.controller.toggleDrawing()
        var panel = try #require(stage.controller.toolbarPanel)
        #expect(panel.frame.midX.rounded() == Screens.leftScreen.frame.midX)
        #expect(panel.frame.minY == Screens.leftScreen.visibleFrame.minY + 24)
        #expect(Screens.leftScreen.visibleFrame.contains(panel.frame))

        // The pointer is on the right screen.
        stage = Stage()
        stage.desk.pointer = CGPoint(x: 1000, y: 100)
        stage.controller.toggleDrawing()
        panel = try #require(stage.controller.toolbarPanel)
        #expect(panel.frame.midX.rounded() == Screens.rightScreen.frame.midX)
        #expect(panel.frame.minY == Screens.rightScreen.visibleFrame.minY + 24)
    }

    @Test func row2_16_atTheNextStartTheToolbarIsAtTheBottomCentreAgain() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        var panel = try #require(stage.controller.toolbarPanel)
        let start = panel.frame.origin
        // The user dragged the toolbar to a different place.
        panel.setFrameOrigin(CGPoint(x: 40, y: 400))
        // The mode changes do not move it back.
        stage.controller.toggleClickThrough()
        stage.controller.toggleClickThrough()
        #expect(panel.frame.origin == CGPoint(x: 40, y: 400))

        stage.controller.toggleDrawing()
        stage.controller.toggleDrawing()
        panel = try #require(stage.controller.toolbarPanel)
        #expect(panel.frame.origin == start)
    }

    @Test func row2_18_oneToolbarServesAllScreens() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        #expect(stage.controller.overlays.count == 2)
        // The toolbar is one panel of its own. No overlay has a toolbar.
        let panel = try #require(stage.controller.toolbarPanel)
        #expect(stage.controller.overlays.allSatisfy { $0 !== panel })
        // It is one level above the overlays, so a click on an overlay cannot cover it.
        #expect(stage.controller.overlays.allSatisfy { panel.level.rawValue > $0.level.rawValue })

        try stage.press("Rectangle")
        try stage.press("Blue")
        stage.session.drag([point(10, 10), point(60, 60)], on: Screens.left.id)
        stage.session.drag([point(10, 10), point(60, 60)], on: Screens.right.id)
        #expect(stage.session.allMarks.map { $0.mark.tool } == [.rectangle, .rectangle])
        #expect(stage.session.allMarks.map { $0.mark.style.color } == [.blue, .blue])
    }

    @Test func row2_19_theToolbarAsksToBeLeftOutOfScreenCaptures() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        let panel = try #require(stage.controller.toolbarPanel)
        #expect(panel.sharingType == .none)
        // The toolbar never takes the keyboard from the overlay, and it stays when the app is not active.
        #expect(!panel.canBecomeKey && !panel.hidesOnDeactivate)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isOpaque && panel.backgroundColor == .clear)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]))
    }

    // MARK: YAZ-2791

    @Test func row3_13_theTimerExistsOnlyWhileAFadeOrHoldMarkExists() {
        let stage = Stage()
        let controller = stage.controller, session = stage.session
        controller.toggleDrawing()
        #expect(controller.timer == nil)
        session.drawLine(row: 0)
        #expect(controller.timer == nil)

        session.setStay(.fade)
        #expect(controller.timer == nil)
        session.drawLine(row: 1)
        let timer = controller.timer
        #expect(timer?.isValid == true)
        // A second Fade mark uses the same timer.
        session.drawLine(row: 2)
        #expect(controller.timer === timer)

        // The clocks remove the two Fade marks: the timer stops.
        stage.clock.time += 2
        controller.tick()
        #expect(session.allMarks.map { $0.stay } == [.sticky])
        #expect(controller.timer == nil)
        #expect(timer?.isValid == false)

        // A Hold mark starts it again, and Clear all stops it.
        session.setStay(.hold)
        session.drawLine(row: 3)
        #expect(controller.timer != nil)
        controller.clearAll()
        #expect(controller.timer == nil)
    }

    @Test func row3_3_theTickSetsTheStrengthOfTheLayerOfAFadeMark() throws {
        let stage = Stage()
        let controller = stage.controller, session = stage.session
        controller.toggleDrawing()
        session.drawLine(row: 0)
        session.setStay(.fade)
        session.drawLine(row: 1)
        let view = controller.overlays[0].overlayView
        let sticky = try #require(view.markLayers[session.allMarks[0].id])
        let fade = try #require(view.markLayers[session.allMarks[1].id])
        #expect(sticky.opacity == 1 && fade.opacity == 1)

        stage.clock.time += 1.5
        controller.tick()
        #expect(sticky.opacity == 1 && fade.opacity == 0.5)
        stage.clock.time += 0.5
        controller.tick()
        #expect(view.markLayers.count == 1)
        #expect(fade.superlayer == nil && sticky.superlayer != nil)
    }

    // MARK: YAZ-2792

    @Test func row4_1_clickThroughMakesTheOverlaysIgnoreTheMouseAndTheKeyboard() throws {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.drawLine()
        let overlays = controller.overlays

        controller.toggleClickThrough()
        #expect(controller.mode == .clickThrough)
        #expect(stage.modes == [.drawing, .clickThrough])
        // The same windows stay, with their marks.
        #expect(controller.overlays.elementsEqual(overlays) { $0 === $1 })
        #expect(controller.overlays[0].overlayView.markLayers.count == 1)
        for overlay in controller.overlays {
            // Clicks, drags and scrolls go to the apps below, and the overlay cannot take the keyboard.
            #expect(overlay.ignoresMouseEvents)
            #expect(!overlay.canBecomeKey)
        }
    }

    @Test func row4_2_theToolbarIsDimInClickThroughAndStillTakesClicks() throws {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.drawLine()
        let panel = try #require(controller.toolbarPanel)
        #expect(panel.alphaValue == 1)

        controller.toggleClickThrough()
        #expect(panel.alphaValue == 0.5)
        #expect(!panel.ignoresMouseEvents)

        // A click on a tool goes back to mode drawing with that tool.
        try stage.press("Arrow")
        #expect(controller.mode == .drawing && stage.session.tool == .arrow)
        #expect(panel.alphaValue == 1)
        #expect(controller.overlays.allSatisfy { !$0.ignoresMouseEvents })

        // Clear all does its work in click-through, and the mode stays.
        controller.toggleClickThrough()
        try stage.press("Clear all")
        #expect(stage.session.markCount == 0 && controller.mode == .clickThrough)
        // Close does its work.
        try stage.press("Close")
        #expect(controller.mode == .off && controller.overlays.isEmpty && controller.toolbarPanel == nil)
        #expect(stage.modes == [.drawing, .clickThrough, .drawing, .clickThrough, .off])
    }

    @Test func row4_3_backInModeDrawingTheOverlaysTakeTheMouseAndTheKeyboardAgain() {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        controller.toggleClickThrough()
        controller.toggleClickThrough()
        #expect(controller.mode == .drawing)
        for overlay in controller.overlays {
            #expect(!overlay.ignoresMouseEvents)
            #expect(overlay.canBecomeKey)
        }
        #expect(controller.toolbarPanel?.alphaValue == 1)
    }

    @Test func row4_4_theClickThroughHotkeyDoesNothingWhenTheModeIsOff() {
        let stage = Stage()
        stage.controller.toggleClickThrough()
        #expect(stage.controller.mode == .off)
        #expect(stage.modes.isEmpty)
        #expect(stage.controller.overlays.isEmpty)
    }

    @Test func row4_6_theKeptMarksShowAgainInTheNewOverlays() {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.drawLine(row: 1, on: Screens.left.id)
        stage.session.drawLine(on: Screens.right.id)
        controller.toggleDrawing()

        controller.toggleDrawing()
        #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [2, 1])
    }

    @Test func row4_14_withTheModeOffNoWindowNoTimerAndNoObserverExists() {
        let stage = Stage()
        let controller = stage.controller
        // Before the first use.
        #expect(controller.overlays.isEmpty && controller.toolbarPanel == nil)
        #expect(controller.timer == nil && controller.screenObserver == nil)

        controller.toggleDrawing()
        stage.session.drawLine(row: 0)
        stage.session.setStay(.hold)
        stage.session.drawLine(row: 1)
        let windows: [NSWindow] = controller.overlays + [controller.toolbarPanel].compactMap { $0 }
        let timer = controller.timer
        #expect(windows.count == 3 && timer != nil && controller.screenObserver != nil)

        // Esc turns drawing off in the same way as the draw hotkey.
        stage.session.escape()
        #expect(controller.mode == .off)
        #expect(controller.overlays.isEmpty && controller.toolbarPanel == nil)
        #expect(controller.timer == nil && timer?.isValid == false)
        #expect(controller.screenObserver == nil)
        #expect(windows.allSatisfy { !$0.isVisible })

        // The kept marks are data only: a tick and a change of the screens do nothing.
        controller.toggleDrawing()
        stage.session.undo()
        controller.toggleDrawing()
        #expect(stage.session.markCount == 1)
        stage.clock.time += 3600
        controller.tick()
        controller.screensChanged()
        #expect(controller.overlays.isEmpty && controller.timer == nil && stage.session.markCount == 1)
    }

    // MARK: The contract with the shell

    @Test func theMenuRowClearAllClearsAndOneUndoBringsTheMarksBack() {
        let stage = Stage()
        let draw: DrawControlling = stage.controller
        draw.toggleDrawing()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.drawLine(on: Screens.right.id)

        draw.clearAll()
        #expect(stage.session.markCount == 0)
        #expect(draw.mode == .drawing)
        stage.session.undo()
        #expect(stage.session.markCount == 2)
    }

    @Test func thePublicInitMakesAControllerThatIsOffAndShowsNothing() {
        let store = TestDefaults()
        let draw: DrawControlling = DrawController(defaults: store.defaults)
        #expect(draw.mode == .off)
        draw.toggleClickThrough()
        draw.clearAll()
        #expect(draw.mode == .off)
    }

    /// The full flow with no window on a screen: draw on, a mark, Undo, click-through, draw off
    /// with the draw hotkey, draw on, and the Sticky mark is back.
    @Test func endToEnd_drawUndoClickThroughOffAndTheStickyMarkIsBack() throws {
        let stage = Stage()
        let draw: DrawControlling = stage.controller
        let session = stage.session

        // The draw hotkey: drawing is on, with one overlay for each screen and the toolbar.
        draw.toggleDrawing()
        #expect(draw.mode == .drawing)
        #expect(stage.controller.overlays.count == 2 && stage.controller.toolbarPanel != nil)
        let left = stage.controller.overlays[0].overlayView

        // Two Sticky marks and one Fade mark.
        session.drag([point(100, 100), point(200, 150), point(300, 120)], on: Screens.left.id)
        session.drag([point(100, 200), point(300, 200)], on: Screens.left.id)
        try stage.press("Fade")
        session.drag([point(50, 50), point(150, 60)], on: Screens.right.id)
        let sticky = session.marks(on: Screens.left.id)[0]
        #expect(session.markCount == 3)
        #expect(left.markLayers.count == 2)
        #expect(stage.controller.timer != nil)

        // Undo two times, with the button: the Fade mark and the second line go away.
        try stage.press("Undo")
        try stage.press("Undo")
        #expect(session.allMarks == [sticky])
        #expect(left.markLayers.count == 1)
        #expect(stage.controller.timer == nil)
        // Redo brings the second line back, and Undo takes it away again.
        try stage.press("Redo")
        #expect(session.markCount == 2)
        try stage.press("Undo")

        // A new Fade mark, and then the click-through hotkey: the marks stay and the clocks continue.
        session.drag([point(50, 50), point(150, 60)], on: Screens.right.id)
        draw.toggleClickThrough()
        #expect(draw.mode == .clickThrough)
        #expect(session.markCount == 2)
        #expect(stage.controller.overlays.allSatisfy { $0.ignoresMouseEvents })
        #expect(stage.controller.toolbarPanel?.alphaValue == 0.5)
        #expect(stage.controller.timer != nil)

        // The draw hotkey: drawing is off. The windows and the timer are gone. The Sticky mark is kept.
        draw.toggleDrawing()
        #expect(draw.mode == .off)
        #expect(stage.controller.overlays.isEmpty && stage.controller.toolbarPanel == nil)
        #expect(stage.controller.timer == nil && stage.controller.screenObserver == nil)
        #expect(session.allMarks == [sticky])

        // The draw hotkey again: the Sticky mark is back at the same place on the same screen.
        draw.toggleDrawing()
        #expect(draw.mode == .drawing)
        #expect(session.marks(on: Screens.left.id) == [sticky])
        #expect(session.marks(on: Screens.right.id).isEmpty)
        #expect(stage.controller.overlays.map { $0.overlayView.markLayers.count } == [1, 0])
        #expect(stage.controller.overlays.allSatisfy { !$0.ignoresMouseEvents })
        #expect(stage.controller.toolbarPanel?.alphaValue == 1)

        #expect(stage.modes == [.drawing, .clickThrough, .off, .drawing])
        #expect(stage.nothingIsOnAScreen)
    }
}
