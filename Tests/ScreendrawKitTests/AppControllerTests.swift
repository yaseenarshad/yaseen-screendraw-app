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

    private func row(_ title: String, of app: AppController) throws -> NSMenuItem {
        try #require(app.statusMenu.menu.item(withTitle: title))
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
        #expect(titles == ["Start drawing", "Click through", "Clear all", "-", "Settings…", "-", "Quit"])

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

    /// The hotkey side of rows 4.1, 4.3 and 4.4: the click-through hotkey asks the drawing part.
    @Test func theClickThroughHotKeyTogglesClickThrough() {
        startApp()
        // Mode off: the shell still tells the drawing part, and the drawing part does nothing (row 4.4).
        hotKeys.press(controlOptionC)
        #expect(draw.calls == ["toggleClickThrough"])
        #expect(draw.mode == .off)

        hotKeys.press(controlOptionD)
        hotKeys.press(controlOptionC)
        #expect(draw.mode == .clickThrough)
        hotKeys.press(controlOptionC)
        #expect(draw.mode == .drawing)
        #expect(draw.calls == ["toggleClickThrough", "toggleDrawing", "toggleClickThrough", "toggleClickThrough"])
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

    @Test func row4_15_clickThroughIsAvailableOnlyWhenTheModeIsNotOff() throws {
        let app = startApp()
        let clickThroughRow = try row("Click through", of: app)
        #expect(clickThroughRow.isEnabled == false)
        // A click on the row does nothing in mode off.
        click(clickThroughRow)
        #expect(draw.calls.isEmpty)

        draw.toggleDrawing()
        #expect(clickThroughRow.isEnabled == true)
        draw.toggleClickThrough()
        #expect(clickThroughRow.isEnabled == true)
        draw.toggleDrawing()
        #expect(clickThroughRow.isEnabled == false)
        // The other rows that change the marks stay available.
        #expect(try row("Start drawing", of: app).isEnabled)
        #expect(try row("Clear all", of: app).isEnabled)
        #expect(try row("Quit", of: app).isEnabled)
    }

    /// The menu follows the mode that the drawing part has when the app starts.
    @Test func theMenuShowsTheModeOfTheDrawingPartAtTheStart() throws {
        draw.toggleDrawing()
        let app = startApp()
        #expect(app.statusMenu.menu.item(withTitle: "Stop drawing") != nil)
        #expect(try row("Click through", of: app).isEnabled)
        #expect(app.statusMenu.symbolName == "pencil.tip.crop.circle.fill")
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
