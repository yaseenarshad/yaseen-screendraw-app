import AppKit
import Carbon.HIToolbox
@testable import ScreendrawKit
import Testing

/// The gear of the toolbar (D13, YAZ-2827), out of sight: rows 2.40 to 2.45.
///
/// The drawing part and the shell are real. What "Settings…" does is a list that the test reads:
/// no test shows the settings window.
@MainActor @Suite struct SettingsGearTests {
    @MainActor final class Stage {
        let store = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        let controller: DrawController
        let app: AppController
        /// The mode at each moment that the settings window opened.
        var opened: [DrawMode] = []

        init() {
            controller = DrawController(
                defaults: store, now: { 0 }, screens: { [Screens.leftScreen] }, pointer: { CGPoint(x: 400, y: 300) }
            )
            app = AppController(
                draw: controller, store: SettingsStore(defaults: store), hotKeys: hotKeys, loginItem: FakeLoginItem()
            )
            // The real one shows a window. A test must not.
            app.openSettings = { [unowned self] in self.opened.append(self.controller.mode) }
            app.start()
        }

        var session: DrawSession { controller.session }

        /// A click on the gear of the toolbar.
        func pressTheGear() throws {
            session.openSettings()
        }

        /// The overlay gets Command-comma. Nothing presses a key: the test gives the event to the view.
        func commandComma(_ flags: NSEvent.ModifierFlags = .command) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: UInt16(kVK_ANSI_Comma)
            ))
            return try #require(controller.overlays.first).overlayView.performKeyEquivalent(with: event)
        }

        /// The menu row "Click through" has its check mark.
        var menuShowsClickThrough: Bool {
            app.statusMenu.menu.item(withTitle: "Click through")?.state == .on
        }
    }

    @Test func row2_41_theGearInModeDrawingPausesThePenAndThenOpensTheSettings() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()
        let panel = try #require(stage.controller.toolbarPanel)

        try stage.pressTheGear()
        #expect(stage.controller.mode == .clickThrough)
        // The mode was click-through before the settings window opened, so the window gets the mouse.
        #expect(stage.opened == [.clickThrough])
        // The marks stay, the toolbar is dim, and the overlays let the clicks pass.
        #expect(stage.session.markCount == 1)
        #expect(stage.controller.overlays[0].overlayView.markLayers.count == 1)
        #expect(panel.alphaValue == 0.5)
        #expect(stage.controller.overlays.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey })
        // The menu follows the mode, as with the click-through hotkey.
        #expect(stage.menuShowsClickThrough)
    }

    @Test func row2_42_theGearInClickThroughOpensTheSettingsAndTheModeStays() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()
        stage.controller.toggleClickThrough()
        let overlays = stage.controller.overlays

        try stage.pressTheGear()
        #expect(stage.opened == [.clickThrough])
        #expect(stage.controller.mode == .clickThrough && stage.session.markCount == 1)
        // No change of the mode: the overlay windows are the same windows.
        #expect(zip(stage.controller.overlays, overlays).allSatisfy { $0 === $1 })
    }

    @Test func row2_43_commandCommaInModeDrawingDoesTheSameAsTheGear() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()

        // Shift-Command-comma and Control-Command-comma are not this key.
        #expect(try !stage.commandComma([.command, .shift]))
        #expect(try !stage.commandComma([.command, .control]))
        #expect(stage.controller.mode == .drawing && stage.opened.isEmpty)

        #expect(try stage.commandComma())
        #expect(stage.controller.mode == .clickThrough)
        #expect(stage.opened == [.clickThrough])
        #expect(stage.session.markCount == 1)
        // In click-through no overlay can have the keyboard, so Command-comma goes to the app below.
        #expect(stage.controller.overlays.allSatisfy { !$0.canBecomeKey })
    }

    @Test func row2_44_aTextThatIsOpenIsFinishedFirst() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.selectTool(.text)
        stage.session.click(at: point(100, 100))
        stage.session.textChanged("note")
        #expect(stage.session.textEdit != nil && stage.session.markCount == 0)

        // The text field is open, and the overlay still gets Command-comma first.
        #expect(try stage.commandComma())
        #expect(stage.session.textEdit == nil)
        #expect(stage.session.allMarks.map { $0.mark.text } == ["note"])
        #expect(stage.controller.mode == .clickThrough && stage.opened == [.clickThrough])

        // An empty text makes no mark (row 2.8).
        stage.session.selectTool(.text)
        #expect(stage.controller.mode == .drawing)
        stage.session.click(at: point(200, 200))
        try stage.pressTheGear()
        #expect(stage.session.textEdit == nil && stage.session.markCount == 1)
        #expect(stage.opened == [.clickThrough, .clickThrough])
    }

    @Test func row2_44_aDragInProgressIsFinishedFirst() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.selectTool(.rectangle)
        stage.session.pointerDown(at: point(50, 50), on: Screens.left.id)
        stage.session.pointerDragged(to: point(150, 120))
        #expect(stage.session.markCount == 0 && stage.session.draft(on: Screens.left.id) != nil)

        try stage.pressTheGear()
        #expect(stage.session.draft(on: Screens.left.id) == nil)
        #expect(stage.session.allMarks.map { $0.mark.points } == [[point(50, 50), point(150, 120)]])
        #expect(stage.controller.mode == .clickThrough && stage.opened == [.clickThrough])
        // The pointer up of that drag arrives later. It draws nothing more.
        stage.session.pointerUp(at: point(300, 300))
        #expect(stage.session.markCount == 1)
    }

    /// The drawing part does not know the settings window, so the close of that window cannot
    /// change the mode. Only the click-through hotkey or a tool goes back to mode drawing.
    @Test func row2_45_afterTheSettingsTheModeStaysClickThroughUntilTheHotkeyOrATool() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()
        try stage.pressTheGear()
        #expect(stage.controller.mode == .clickThrough)

        // The click-through hotkey goes back to drawing (row 4.3).
        stage.hotKeys.press(HotKeyKind.clickThrough.startValue)
        #expect(stage.controller.mode == .drawing && !stage.menuShowsClickThrough)

        // A click on a tool goes back to drawing with that tool (row 4.2).
        try stage.pressTheGear()
        #expect(stage.controller.mode == .clickThrough)
        try #require(stage.controller.toolbarPanel).toolbarView.press("Arrow")
        #expect(stage.controller.mode == .drawing && stage.session.tool == .arrow)
        #expect(stage.session.markCount == 1)
        #expect(stage.opened == [.clickThrough, .clickThrough])
    }

    @Test func theGearDoesNothingWhileTheModeIsOff() throws {
        let stage = Stage()
        stage.session.openSettings()
        #expect(stage.opened.isEmpty && stage.controller.mode == .off)
        #expect(stage.controller.overlays.isEmpty && stage.controller.toolbarPanel == nil)
    }

    /// The shell knows the drawing part only as a `DrawControlling`: it sets one closure there.
    @Test func theShellGivesTheDrawingPartWhatSettingsDoes() {
        let draw = FakeDrawControl()
        let app = AppController(
            draw: draw, store: SettingsStore(defaults: MemoryDefaults()), hotKeys: FakeHotKeyRegistrar(), loginItem: FakeLoginItem()
        )
        var opened = 0
        app.openSettings = { opened += 1 }
        // Before the start, the closure of the drawing part does nothing.
        draw.onOpenSettings()
        #expect(opened == 0)

        app.start()
        draw.onOpenSettings()
        #expect(opened == 1)
        // The menu row "Settings…" does the same.
        if let row = app.statusMenu.menu.item(withTitle: "Settings…") { click(row) }
        #expect(opened == 2)
    }
}
