import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ScreendrawKit

@MainActor
@Suite struct SettingsModelTests {
    private let controlOptionD = HotKeyKind.draw.startValue
    private let controlOptionC = HotKeyKind.clickThrough.startValue
    private let controlOptionS = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option])
    private let escape = HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [])

    /// A model on its own settings, with the two hotkeys registered as at the start of the app.
    private func makeModel(
        defaults: UserDefaults = MemoryDefaults(),
        hotKeys: FakeHotKeyRegistrar = FakeHotKeyRegistrar(),
        loginItem: FakeLoginItem = FakeLoginItem()
    ) -> SettingsModel {
        let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: loginItem)
        model.registerHotKeys()
        return model
    }

    @Test func row5_2_aNewKeyWorksAtOnceAndIsStored() {
        let defaults = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        var pressed: [HotKeyKind] = []
        hotKeys.onHotKey = { pressed.append($0) }
        var told: [String] = []
        model.onHotKeyChanged = { kind, combo in told.append("\(kind) \(combo.text)") }
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])

        model.startRecording(.draw)
        #expect(model.keyDown(controlOptionS) == true)
        #expect(model.recording == nil)
        #expect(model.hotKey(.draw) == controlOptionS)
        #expect(model.hotKeyProblem(.draw) == nil)
        // The new hotkey works at once, the old one does not, and the other hotkey works again.
        #expect(hotKeys.registered == [.draw: controlOptionS, .clickThrough: controlOptionC])
        hotKeys.press(controlOptionD)
        #expect(pressed.isEmpty)
        hotKeys.press(controlOptionS)
        hotKeys.press(controlOptionC)
        #expect(pressed == [.draw, .clickThrough])
        // The menu shows the hotkey, so the app is told.
        #expect(told == ["draw ⌃⌥S"])
        // A new store on the same settings: the hotkey is stored.
        #expect(SettingsStore(defaults: defaults).hotKey(.draw) == controlOptionS)
        #expect(SettingsStore(defaults: defaults).hotKey(.clickThrough) == controlOptionC)

        // The click-through hotkey changes the same way. A function key needs no modifier.
        let f6 = HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: [])
        model.startRecording(.clickThrough)
        #expect(model.keyDown(f6) == true)
        #expect(hotKeys.registered == [.draw: controlOptionS, .clickThrough: f6])
        #expect(told == ["draw ⌃⌥S", "clickThrough F6"])
        #expect(SettingsStore(defaults: defaults).hotKey(.clickThrough) == f6)

        // The key that was the draw hotkey is free now for the other hotkey.
        model.startRecording(.clickThrough)
        #expect(model.keyDown(controlOptionD) == true)
        #expect(model.hotKeyProblem(.clickThrough) == nil)
        #expect(hotKeys.registered == [.draw: controlOptionS, .clickThrough: controlOptionD])
    }

    @Test func row5_3_aKeyWithNoModifierIsRefusedWithTheReason() {
        let defaults = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        var told = 0
        model.onHotKeyChanged = { _, _ in told += 1 }

        let refusedKeys = [
            HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: []),
            HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: .shift),
            HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: []),
        ]
        for kind in HotKeyKind.allCases {
            for key in refusedKeys {
                model.startRecording(kind)
                #expect(model.keyDown(key) == true)
                #expect(model.recording == nil)
                #expect(model.hotKeyProblem(kind) == "A hotkey needs ⌘, ⌃ or ⌥ with the key, or a function key.")
                // The old hotkeys stay, and the two work again.
                #expect(model.hotKey(kind) == kind.startValue)
                #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])
            }
            // The red line is only below the row that recorded.
            #expect(model.hotKeyProblem(kind.other) == nil)
            // It stays while the recorder of the other row is not used, and "Change…" of each row removes it.
            for next in [kind, kind.other] {
                model.startRecording(kind)
                _ = model.keyDown(refusedKeys[0])
                #expect(model.hotKeyProblem(kind) != nil)
                model.startRecording(next)
                #expect(model.hotKeyProblem(kind) == nil)
                model.cancelRecording()
                #expect(model.hotKeyProblem(kind) == nil)
            }
        }
        #expect(told == 0)
        #expect(defaults.object(forKey: "drawHotKeyCode") == nil)
        #expect(defaults.object(forKey: "clickThroughHotKeyCode") == nil)
    }

    @Test func row5_4_theSameKeyForTheTwoHotKeysIsRefused() {
        let defaults = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        var told = 0
        model.onHotKeyChanged = { _, _ in told += 1 }

        for kind in HotKeyKind.allCases {
            model.startRecording(kind)
            #expect(model.keyDown(kind.other.startValue) == true)
            #expect(model.recording == nil)
            #expect(model.hotKeyProblem(kind) == "The two hotkeys must be different.")
            #expect(model.hotKeyProblem(kind.other) == nil)
            #expect(model.hotKey(kind) == kind.startValue)
            #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])
        }
        #expect(told == 0)
        #expect(SettingsStore(defaults: defaults).hotKey(.draw) == controlOptionD)
        #expect(SettingsStore(defaults: defaults).hotKey(.clickThrough) == controlOptionC)
    }

    @Test func row5_5_aKeyThatMacOSRefusesKeepsTheOldHotKey() {
        let defaults = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        hotKeys.refused = [controlOptionS]
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        var pressed: [HotKeyKind] = []
        hotKeys.onHotKey = { pressed.append($0) }
        var told = 0
        model.onHotKeyChanged = { _, _ in told += 1 }

        model.startRecording(.draw)
        #expect(model.keyDown(controlOptionS) == true)
        #expect(model.recording == nil)
        #expect(model.hotKeyProblem(.draw) == "macOS refused this hotkey. A different app can have it.")
        #expect(model.hotKeyProblem(.clickThrough) == nil)
        #expect(model.hotKey(.draw) == controlOptionD)
        #expect(SettingsStore(defaults: defaults).hotKey(.draw) == controlOptionD)
        #expect(told == 0)
        // The old hotkey still works, and the other one too.
        hotKeys.press(controlOptionD)
        hotKeys.press(controlOptionC)
        #expect(pressed == [.draw, .clickThrough])
    }

    /// Row 5.5 at the start of the app: the stored hotkey cannot be registered.
    @Test func row5_5_aRefusedHotKeyAtTheStartShowsTheRedLineAndTheOtherOneWorks() {
        let hotKeys = FakeHotKeyRegistrar()
        hotKeys.refused = [controlOptionD]
        let model = makeModel(hotKeys: hotKeys)
        #expect(model.hotKeyProblem(.draw) == SettingsModel.refusedText)
        #expect(model.hotKeyProblem(.clickThrough) == nil)
        #expect(model.hotKey(.draw) == controlOptionD)
        #expect(hotKeys.registered == [.clickThrough: controlOptionC])

        // The line tells the state of the hotkey. It is there again after the recorder of the other row.
        model.startRecording(.clickThrough)
        #expect(model.hotKeyProblem(.draw) == nil)
        model.cancelRecording()
        #expect(model.hotKeyProblem(.draw) == SettingsModel.refusedText)

        // A different key still works then, and the red line goes away.
        model.startRecording(.draw)
        #expect(model.keyDown(controlOptionS) == true)
        #expect(model.hotKeyProblem(.draw) == nil)
        #expect(hotKeys.registered == [.draw: controlOptionS, .clickThrough: controlOptionC])
    }

    @Test func row5_6_theRecorderPausesTheTwoHotKeysAndEscStopsIt() {
        let defaults = MemoryDefaults()
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        var pressed: [HotKeyKind] = []
        hotKeys.onHotKey = { pressed.append($0) }
        var told = 0
        model.onHotKeyChanged = { _, _ in told += 1 }

        // A key in the window while no row records is not for the model.
        #expect(model.keyDown(controlOptionS) == false)

        for kind in HotKeyKind.allCases {
            model.startRecording(kind)
            #expect(model.recording == kind)
            // The two hotkeys are paused: a press changes no mode.
            #expect(hotKeys.registered.isEmpty)
            hotKeys.press(controlOptionD)
            hotKeys.press(controlOptionC)
            #expect(pressed.isEmpty)

            // Esc stops the recorder with no change, also with a modifier.
            let key = (kind == .draw) ? escape : HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: .command)
            #expect(model.keyDown(key) == true)
            #expect(model.recording == nil)
            #expect(model.hotKeyProblem(kind) == nil)
            #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])
        }

        // The window closes during a recording: the same as Esc.
        model.startRecording(.draw)
        model.cancelRecording()
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])

        // "Change…" of the other row during a recording: only that row records.
        model.startRecording(.draw)
        model.startRecording(.clickThrough)
        #expect(model.recording == .clickThrough)
        #expect(hotKeys.registered.isEmpty)
        model.cancelRecording()

        // The user can record the key that is this hotkey now. It is accepted, because it was paused.
        model.startRecording(.draw)
        #expect(model.keyDown(controlOptionD) == true)
        #expect(model.hotKeyProblem(.draw) == nil)
        #expect(model.hotKey(.draw) == controlOptionD)
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])

        hotKeys.press(controlOptionD)
        #expect(pressed == [.draw])
        #expect(told == 1)
    }

    /// Row 5.7 in the model: the window and the hotkeys use the start values.
    @Test func row5_7_theModelUsesTheStartValuesForStoredValuesThatAreNotValid() {
        let defaults = MemoryDefaults()
        defaults.set("d", forKey: "drawHotKeyCode")
        defaults.set(0, forKey: "drawHotKeyModifiers")
        defaults.set(kVK_ANSI_A, forKey: "clickThroughHotKeyCode")
        defaults.set(0, forKey: "clickThroughHotKeyModifiers")
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(defaults: defaults, hotKeys: hotKeys)
        #expect(model.hotKey(.draw).text == "⌃⌥D")
        #expect(model.hotKey(.clickThrough).text == "⌃⌥C")
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])
    }

    @Test func row5_8_theFirstStartTurnsOpenAtLoginOnOneTime() {
        let defaults = MemoryDefaults()
        let loginItem = FakeLoginItem()
        let model = makeModel(defaults: defaults, loginItem: loginItem)
        #expect(model.openAtLogin == false)

        model.registerLoginItemAtFirstStart()
        #expect(loginItem.calls == [true])
        #expect(model.openAtLogin == true)
        #expect(model.loginItemProblem == nil)
        #expect(SettingsStore(defaults: defaults).loginItemWasTried == true)

        // The user turns it off in System Settings. A later start does not turn it on again.
        loginItem.isEnabled = false
        let later = makeModel(defaults: defaults, loginItem: loginItem)
        later.registerLoginItemAtFirstStart()
        #expect(loginItem.calls == [true])
        #expect(later.openAtLogin == false)

        // macOS has it on before the first start: the app does not call macOS.
        let isOn = FakeLoginItem()
        isOn.isEnabled = true
        let third = makeModel(loginItem: isOn)
        third.registerLoginItemAtFirstStart()
        #expect(isOn.calls.isEmpty)
        #expect(third.openAtLogin == true)
    }

    @Test func row5_8_whenMacOSRefusesAtTheFirstStartTheSwitchIsOffAndTheWindowTellsWhy() {
        let loginItem = FakeLoginItem()
        loginItem.refuses = true
        let model = makeModel(loginItem: loginItem)
        model.registerLoginItemAtFirstStart()
        // There is no second try.
        model.registerLoginItemAtFirstStart()
        #expect(loginItem.calls == [true])
        #expect(model.openAtLogin == false)
        #expect(model.loginItemProblem == "Operation not permitted")

        // macOS gives no error, but the state does not change: the window tells that too.
        let ignoring = FakeLoginItem()
        ignoring.ignores = true
        let second = makeModel(loginItem: ignoring)
        second.registerLoginItemAtFirstStart()
        #expect(second.openAtLogin == false)
        #expect(second.loginItemProblem == SettingsModel.loginItemNotChangedText)
    }

    /// Row 5.8 outside the `.app` bundle (`swift run`): macOS has nothing to register.
    @Test func row5_8_outsideTheBundleTheSwitchIsOffAndTheWindowTellsWhy() {
        let defaults = MemoryDefaults()
        let loginItem = FakeLoginItem()
        loginItem.isAvailable = false
        loginItem.isEnabled = true
        let model = makeModel(defaults: defaults, loginItem: loginItem)
        model.registerLoginItemAtFirstStart()
        model.setOpenAtLogin(true)
        #expect(loginItem.calls.isEmpty)
        #expect(model.openAtLogin == false)
        #expect(model.loginItemIsAvailable == false)
        #expect(model.loginItemNote == "Open at login works only in the installed app.")
        // The one try is still free for the installed app.
        #expect(SettingsStore(defaults: defaults).loginItemWasTried == false)
    }

    @Test func row5_9_theSwitchShowsTheRealStateOfMacOS() {
        let defaults = MemoryDefaults()
        let loginItem = FakeLoginItem()
        // The first start was done, but macOS tells off. The switch shows off.
        SettingsStore(defaults: defaults).loginItemWasTried = true
        let model = makeModel(defaults: defaults, loginItem: loginItem)
        #expect(model.openAtLogin == false)
        #expect(model.loginItemNote == nil)

        // A change in System Settings shows after a refresh (the window does one when it comes to the front).
        loginItem.isEnabled = true
        model.refreshOpenAtLogin()
        #expect(model.openAtLogin == true)

        model.setOpenAtLogin(false)
        #expect(loginItem.calls == [false])
        #expect(model.openAtLogin == false)
        #expect(model.loginItemProblem == nil)

        // macOS refuses: the switch goes back, and the red line shows the reason.
        loginItem.refuses = true
        model.setOpenAtLogin(true)
        #expect(model.openAtLogin == false)
        #expect(model.loginItemProblem == "Operation not permitted")

        // No error, but no change: the switch goes back with a line too.
        loginItem.refuses = false
        loginItem.ignores = true
        model.setOpenAtLogin(true)
        #expect(model.openAtLogin == false)
        #expect(model.loginItemProblem == SettingsModel.loginItemNotChangedText)

        // A change that works removes the red line.
        loginItem.ignores = false
        model.setOpenAtLogin(true)
        #expect(model.openAtLogin == true)
        #expect(model.loginItemProblem == nil)
    }

    /// The delegate calls of the settings window, with no window on a screen. The test makes the
    /// calls that AppKit makes. The key monitor is local: it sees only the keys of this process.
    @Test func row5_6_theRecorderAndTheKeyMonitorStopWhenTheWindowLosesTheKeyboard() {
        let hotKeys = FakeHotKeyRegistrar()
        let model = makeModel(hotKeys: hotKeys)
        let controller = SettingsWindowController(model: model)
        let became = Notification(name: NSWindow.didBecomeKeyNotification)
        let resigned = Notification(name: NSWindow.didResignKeyNotification)
        // Before the window has the keyboard, no monitor exists.
        #expect(controller.keyMonitor == nil)

        controller.windowDidBecomeKey(became)
        #expect(controller.keyMonitor != nil)
        model.startRecording(.draw)
        #expect(hotKeys.registered.isEmpty)

        // A different window takes the keyboard (the overlay, or a different app).
        controller.windowDidResignKey(resigned)
        #expect(controller.keyMonitor == nil)
        #expect(model.recording == nil)
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])

        // The window closes while it records.
        controller.windowDidBecomeKey(became)
        model.startRecording(.clickThrough)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(controller.keyMonitor == nil)
        #expect(model.recording == nil)
        #expect(hotKeys.registered == [.draw: controlOptionD, .clickThrough: controlOptionC])
    }

    /// The form lays out with no window. Each line for a problem makes it higher.
    @Test func theFormHasASizeAndGrowsWithTheProblemLines() {
        let hotKeys = FakeHotKeyRegistrar()
        let loginItem = FakeLoginItem()
        let model = makeModel(hotKeys: hotKeys, loginItem: loginItem)
        @MainActor func size() -> CGSize {
            NSHostingView(rootView: SettingsView(model: model)).fittingSize
        }
        let plain = size()
        #expect(plain.width == 460)
        #expect(plain.height > 100 && plain.height < 400)

        model.startRecording(.draw)
        _ = model.keyDown(controlOptionC)
        #expect(model.hotKeyProblem(.draw) != nil)
        let withHotKeyLine = size().height
        #expect(withHotKeyLine > plain.height)

        loginItem.refuses = true
        model.setOpenAtLogin(true)
        #expect(size().height > withHotKeyLine)
    }
}
