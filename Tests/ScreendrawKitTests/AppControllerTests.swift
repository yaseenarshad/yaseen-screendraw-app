import AppKit
import Carbon.HIToolbox
import Testing
@testable import ScreendrawKit

/// The shell with fakes for each part. No test here makes a status item or a window.
@MainActor
@Suite struct AppControllerTests {
    private let controlOptionD = HotKeyKind.draw.startValue
    private let controlOptionC = HotKeyKind.clickThrough.startValue
    private let positionKey = "NSStatusItem Preferred Position YaseenScreendraw"

    private let draw = FakeDrawControl()
    private let hotKeys = FakeHotKeyRegistrar()
    private let loginItem = FakeLoginItem()
    private let defaults = MemoryDefaults()

    /// The hotkeys and the drawing part hold the app weakly, as `NSApplication` holds its delegate.
    /// This keeps each app of a test until the test ends.
    private final class Keeper {
        var apps: [AppController] = []
    }
    private let keeper = Keeper()

    /// An app that started, with all of `applicationDidFinishLaunching` but the status item.
    @discardableResult
    private func startApp() -> AppController {
        let app = AppController(draw: draw, store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: loginItem)
        app.start()
        keeper.apps.append(app)
        return app
    }

    /// The row "Click through" has the name "Show toolbar" while the mode is off (row 4.20).
    private func row(_ title: String, of app: AppController) throws -> NSMenuItem {
        let menu = app.statusMenu.menu
        if title == "Click through", let row = menu.item(withTitle: "Show toolbar") { return row }
        return try #require(menu.item(withTitle: title))
    }

    @Test func row1_2_aSecondCopyQuits() {
        // Only this process runs.
        #expect(AppController.isSecondCopy(own: 500, running: [500]) == false)
        // macOS does not list this process yet.
        #expect(AppController.isSecondCopy(own: 500, running: []) == false)
        // A different process of the app runs.
        #expect(AppController.isSecondCopy(own: 500, running: [321, 500]) == true)
        #expect(AppController.isSecondCopy(own: 500, running: [321]) == true)
    }

    @Test func row1_13_theMenuHasTheRowsWithTheTwoHotKeys() throws {
        let app = startApp()
        let titles = app.statusMenu.menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Start drawing", "Show toolbar", "Clear all", "-", "Settings…", "-", "Quit"])

        let drawRow = try row("Start drawing", of: app)
        #expect(drawRow.keyEquivalent == "d")
        #expect(drawRow.keyEquivalentModifierMask == [.control, .option])
        let clickThroughRow = try row("Click through", of: app)
        #expect(clickThroughRow.keyEquivalent == "c")
        #expect(clickThroughRow.keyEquivalentModifierMask == [.control, .option])
        // Each row has an action, so a click does something.
        for item in app.statusMenu.menu.items where !item.isSeparatorItem {
            #expect(item.action != nil && item.target != nil, "\(item.title)")
        }
    }

    @Test func row1_13_theFirstRowIsStartDrawingOrStopDrawing() throws {
        let app = startApp()
        let drawRow = try row("Start drawing", of: app)

        draw.toggleDrawing()
        #expect(drawRow.title == "Stop drawing")
        // The draw hotkey also stops in mode click-through.
        draw.toggleClickThrough()
        #expect(draw.mode == .clickThrough)
        #expect(drawRow.title == "Stop drawing")
        draw.toggleDrawing()
        #expect(drawRow.title == "Start drawing")
    }

    /// Row 1.13 with stored hotkeys: the menu shows them from the start.
    @Test func row1_13_theMenuShowsTheStoredHotKeys() throws {
        let store = SettingsStore(defaults: defaults)
        store.setHotKey(HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: [.shift, .command]), for: .draw)
        store.setHotKey(HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: []), for: .clickThrough)
        let app = startApp()

        let drawRow = try row("Start drawing", of: app)
        #expect(drawRow.keyEquivalent == "p")
        #expect(drawRow.keyEquivalentModifierMask == [.shift, .command])
        let clickThroughRow = try row("Click through", of: app)
        #expect(clickThroughRow.keyEquivalent.unicodeScalars.first?.value == UInt32(NSF6FunctionKey))
        #expect(clickThroughRow.keyEquivalentModifierMask == [])
    }

    @Test func row1_14_theMenuBarSymbolShowsTheMode() {
        let app = startApp()
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle")

        draw.toggleDrawing()
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle.fill")
        draw.toggleClickThrough()
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle.fill")
        draw.toggleDrawing()
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle")

        // macOS has the two symbols. A name that it does not have would give an empty menu bar icon.
        for mode in [DrawMode.off, .drawing, .clickThrough] {
            #expect(NSImage(systemSymbolName: StatusMenu.symbolName(for: mode), accessibilityDescription: nil) != nil)
        }
        #expect(NSImage(systemSymbolName: "no.such.symbol.of.the.shell", accessibilityDescription: nil) == nil)
    }

    /// The hotkey side of rows 1.3 and 1.7: the draw hotkey asks the drawing part to change the mode.
    @Test func row1_3_and_1_7_theDrawHotKeyTogglesDrawing() {
        startApp()
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])

        hotKeys.press(controlOptionD)
        #expect(draw.calls == ["toggleDrawing"])
        #expect(draw.mode == .drawing)
        hotKeys.press(controlOptionD)
        #expect(draw.calls == ["toggleDrawing", "toggleDrawing"])
        #expect(draw.mode == .off)
    }

    /// The hotkey side of rows 4.1, 4.3 and 4.26: the click-through hotkey asks the drawing part.
    @Test func theClickThroughHotKeyTogglesClickThrough() {
        startApp()
        // Mode off: the hotkey shows the toolbar with the pen paused (row 4.26).
        hotKeys.press(controlOptionC)
        #expect(draw.calls == ["toggleClickThrough"])
        #expect(draw.mode == .clickThrough)

        hotKeys.press(controlOptionC)
        #expect(draw.mode == .drawing)
        hotKeys.press(controlOptionC)
        #expect(draw.mode == .clickThrough)
        hotKeys.press(controlOptionD)
        #expect(draw.mode == .off)
        #expect(draw.calls == ["toggleClickThrough", "toggleClickThrough", "toggleClickThrough", "toggleDrawing"])
    }

    /// Row 1.13: the menu rows do the same as the hotkeys, and "Clear all" clears.
    @Test func theMenuRowsCallTheDrawingPart() throws {
        let app = startApp()
        click(try row("Start drawing", of: app))
        #expect(draw.calls == ["toggleDrawing"])
        #expect(draw.mode == .drawing)

        click(try row("Click through", of: app))
        #expect(draw.calls == ["toggleDrawing", "toggleClickThrough"])
        #expect(draw.mode == .clickThrough)

        click(try row("Clear all", of: app))
        #expect(draw.calls == ["toggleDrawing", "toggleClickThrough", "clearAll"])
        #expect(draw.mode == .clickThrough)

        click(try row("Stop drawing", of: app))
        #expect(draw.mode == .off)
        // "Clear all" is also available in mode off. The drawing part decides what it clears.
        click(try row("Clear all", of: app))
        #expect(draw.calls.last == "clearAll")
    }

    @Test func row4_20_theClickThroughRowIsShowToolbarInModeOff() throws {
        let app = startApp()
        let clickThroughRow = try row("Click through", of: app)
        // Mode off: the row has the name "Show toolbar", and it is available (rows 4.20 and 4.26).
        #expect(clickThroughRow.title == "Show toolbar" && clickThroughRow.isEnabled)
        #expect(clickThroughRow.state == .off)

        // A click shows the toolbar with the pen paused: the mode is click-through (row 4.21).
        click(clickThroughRow)
        #expect(draw.calls == ["toggleClickThrough"])
        #expect(draw.mode == .clickThrough)
        #expect(clickThroughRow.title == "Click through" && clickThroughRow.state == .on)

        // The row then changes between click-through and drawing (rows 4.24 and 4.3).
        click(clickThroughRow)
        #expect(draw.mode == .drawing)
        #expect(clickThroughRow.title == "Click through" && clickThroughRow.state == .off)

        draw.toggleDrawing()
        #expect(clickThroughRow.title == "Show toolbar" && clickThroughRow.isEnabled)
        // The other rows that change the marks stay available.
        #expect(try row("Start drawing", of: app).isEnabled)
        #expect(try row("Clear all", of: app).isEnabled)
    }

    @Test func theClickThroughRowHasACheckMarkOnlyInModeClickThrough() throws {
        let app = startApp()
        let clickThroughRow = try row("Click through", of: app)
        #expect(clickThroughRow.state == .off)
        draw.toggleDrawing()
        #expect(clickThroughRow.state == .off)
        draw.toggleClickThrough()
        #expect(clickThroughRow.state == .on)
        draw.toggleClickThrough()
        #expect(clickThroughRow.state == .off)
        // The draw hotkey in mode click-through turns drawing off, and the check mark goes away.
        draw.toggleClickThrough()
        draw.toggleDrawing()
        #expect(clickThroughRow.state == .off)
        // No other row has a check mark.
        #expect(app.statusMenu.menu.items.allSatisfy { $0.state == .off })
    }

    /// The menu follows the mode that the drawing part has when the app starts.
    @Test func theMenuShowsTheModeOfTheDrawingPartAtTheStart() throws {
        draw.toggleDrawing()
        let app = startApp()
        #expect(app.statusMenu.menu.item(withTitle: "Stop drawing") != nil)
        #expect(try row("Click through", of: app).isEnabled)
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle.fill")
    }

    /// The shell with the real drawing part, and no window on a screen. The Close button, Esc and
    /// a tool of the toolbar change the mode inside the drawing part. The menu and the menu bar
    /// symbol must follow each change.
    @Test func theMenuFollowsTheModeChangesOfTheRealDrawingPart() throws {
        let real = DrawController(
            defaults: defaults, now: { 0 }, screens: { [Screens.leftScreen] }, pointer: { .zero }
        )
        let app = AppController(draw: real, store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: loginItem)
        app.start()
        keeper.apps.append(app)
        let drawRow = try row("Start drawing", of: app)
        let clickThroughRow = try row("Click through", of: app)
        let settingsRow = try row("Settings…", of: app)
        /// The title of the first row, the symbol, and the two rows that follow the mode.
        func menu() -> [String] {
            [
                drawRow.title,
                app.statusMenu.symbolName,
                clickThroughRow.title == "Show toolbar" ? "show toolbar" : (clickThroughRow.state == .on ? "click-through on" : "click-through off"),
                settingsRow.isEnabled ? "settings" : "no settings",
            ]
        }
        let off = ["Start drawing", "pencil.tip.crop.circle", "show toolbar", "settings"]
        let drawing = ["Stop drawing", "pencil.tip.crop.circle.fill", "click-through off", "no settings"]
        let clickThrough = ["Stop drawing", "pencil.tip.crop.circle.fill", "click-through on", "settings"]
        #expect(menu() == off)

        // The draw hotkey, and then the Close button of the toolbar.
        hotKeys.press(controlOptionD)
        #expect(menu() == drawing)
        try #require(real.toolbarPanel).toolbarView.press("Close")
        #expect(real.mode == .off && menu() == off)

        // The draw hotkey, a mark, and then Esc on the overlay.
        hotKeys.press(controlOptionD)
        real.session.drawLine()
        let esc = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: UInt16(kVK_Escape)
        ))
        try #require(real.overlays.first).overlayView.keyDown(with: esc)
        // Esc pauses the pen and removes no mark (row 4.34). The row has its check mark (row 4.44).
        #expect(real.mode == .clickThrough && menu() == clickThrough)
        #expect(real.session.markCount == 1)

        // A click on a tool: the mode is drawing again. Then the click-through hotkey, and a tool again.
        try #require(real.toolbarPanel).toolbarView.press("Arrow")
        #expect(real.mode == .drawing && menu() == drawing)
        hotKeys.press(controlOptionC)
        #expect(menu() == clickThrough)
        try #require(real.toolbarPanel).toolbarView.press("Arrow")
        #expect(real.mode == .drawing && menu() == drawing)

        // The menu row "Stop drawing" in mode click-through.
        click(clickThroughRow)
        #expect(menu() == clickThrough)
        click(drawRow)
        #expect(real.mode == .off && menu() == off)
        #expect(real.overlays.isEmpty && real.toolbarPanel == nil)
    }

    @Test func row5_2_theMenuShowsANewHotKeyAndTheNewKeyChangesTheMode() throws {
        let app = startApp()
        let controlOptionS = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option])

        app.settings.startRecording(.draw)
        #expect(app.settings.keyDown(controlOptionS) == true)
        let drawRow = try row("Start drawing", of: app)
        #expect(drawRow.keyEquivalent == "s")
        #expect(drawRow.keyEquivalentModifierMask == [.control, .option])
        // The other row did not change.
        #expect(try row("Click through", of: app).keyEquivalent == "c")

        hotKeys.press(controlOptionD)
        #expect(draw.mode == .off)
        hotKeys.press(controlOptionS)
        #expect(draw.mode == .drawing)
        #expect(SettingsStore(defaults: defaults).hotKey(.draw) == controlOptionS)
    }

    /// Row 5.5 at the start: the app continues to run, and the menu still changes the mode.
    @Test func row5_5_aRefusedHotKeyAtTheStartDoesNotStopTheApp() throws {
        hotKeys.refused = [controlOptionD]
        let app = startApp()
        #expect(app.settings.hotKeyProblem(.draw) == SettingsModel.refusedText)
        #expect(hotKeys.registered == [.clickThrough: controlOptionC])

        hotKeys.press(controlOptionD)
        #expect(draw.mode == .off)
        click(try row("Start drawing", of: app))
        #expect(draw.mode == .drawing)
        hotKeys.press(controlOptionC)
        #expect(draw.mode == .clickThrough)
    }

    @Test func row5_6_theHotKeysDoNotChangeTheModeWhileTheRecorderListens() {
        let app = startApp()
        app.settings.startRecording(.clickThrough)
        hotKeys.press(controlOptionD)
        hotKeys.press(controlOptionC)
        #expect(draw.calls.isEmpty)

        #expect(app.settings.keyDown(HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [])) == true)
        hotKeys.press(controlOptionD)
        #expect(draw.calls == ["toggleDrawing"])
    }

    @Test func row5_8_theFirstStartOfTheAppTurnsOpenAtLoginOnOneTime() {
        startApp()
        #expect(loginItem.calls == [true])
        #expect(loginItem.isEnabled == true)

        // The user turns it off. The next start of the app leaves it off.
        loginItem.isEnabled = false
        let second = startApp()
        #expect(loginItem.calls == [true])
        #expect(second.settings.openAtLogin == false)
    }

    @Test func row5_10_theStartSetsThePositionOfTheMenuBarIconOnlyWhenNoneExists() {
        #expect(StatusMenu.autosaveName == "YaseenScreendraw")
        #expect(defaults.object(forKey: positionKey) == nil)
        startApp()
        #expect(defaults.object(forKey: positionKey) as? Double == 460)

        // The user moved the icon. The next start keeps that place.
        defaults.set(212.0, forKey: positionKey)
        startApp()
        #expect(defaults.object(forKey: positionKey) as? Double == 212)
    }

    @Test func row5_11_settingsIsAvailableOnlyInModeOffAndClickThrough() throws {
        let app = startApp()
        var opened = 0
        // The real one shows a window. A test must not.
        app.openSettings = { opened += 1 }
        let settingsRow = try row("Settings…", of: app)

        #expect(settingsRow.isEnabled == true)
        click(settingsRow)
        #expect(opened == 1)

        draw.toggleDrawing()
        #expect(settingsRow.isEnabled == false)
        click(settingsRow)
        #expect(opened == 1)

        draw.toggleClickThrough()
        #expect(settingsRow.isEnabled == true)
        click(settingsRow)
        #expect(opened == 2)

        draw.toggleDrawing()
        #expect(settingsRow.isEnabled == true)
    }
}
