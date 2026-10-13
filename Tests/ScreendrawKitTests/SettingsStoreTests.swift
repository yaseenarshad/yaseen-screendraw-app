import AppKit
import Carbon.HIToolbox
import Testing
@testable import ScreendrawKit

@Suite struct SettingsStoreTests {
    private let controlOptionD = HotKeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: [.control, .option])
    private let controlOptionC = HotKeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .option])
    private let positionKey = "NSStatusItem Preferred Position YaseenScreendraw"

    @Test func theStartValues() {
        let store = SettingsStore(defaults: MemoryDefaults())
        #expect(store.hotKey(.draw) == controlOptionD)
        #expect(store.hotKey(.clickThrough) == controlOptionC)
        #expect(store.loginItemWasTried == false)
    }

    @Test func aWrittenValueComesBackFromANewStoreOnTheSameDefaults() {
        let defaults = MemoryDefaults()
        let commandF6 = HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: .command)
        let f5 = HotKeyCombo(keyCode: UInt32(kVK_F5), modifiers: [])

        let first = SettingsStore(defaults: defaults)
        first.setHotKey(commandF6, for: .draw)
        first.setHotKey(f5, for: .clickThrough)
        first.loginItemWasTried = true

        let second = SettingsStore(defaults: defaults)
        #expect(second.hotKey(.draw) == commandF6)
        #expect(second.hotKey(.clickThrough) == f5)
        #expect(second.loginItemWasTried == true)

        // Each hotkey has its own two values.
        #expect(defaults.object(forKey: "drawHotKeyCode") as? Int == kVK_F6)
        #expect(defaults.object(forKey: "clickThroughHotKeyCode") as? Int == kVK_F5)
        #expect(defaults.object(forKey: "clickThroughHotKeyModifiers") as? Int == 0)
    }

    @Test func row5_7_aStoredValueThatIsNotValidGivesTheStartValue() {
        let defaults = MemoryDefaults()
        let store = SettingsStore(defaults: defaults)
        let command = Int(NSEvent.ModifierFlags.command.rawValue)

        // Each case: the two values of one hotkey as they are on disk.
        let broken: [(code: Any?, modifiers: Any?)] = [
            ("d", command),                                          // the code is not a number
            (kVK_ANSI_A, "command"),                                 // the modifiers are not a number
            (kVK_ANSI_A, nil),                                       // one value is missing
            (nil, command),                                          // one value is missing
            (-1, command),                                           // not a key code
            (4000, command),                                         // not a key code
            (kVK_ANSI_A, -5),                                        // not a set of modifiers
            (kVK_ANSI_A, Int(NSEvent.ModifierFlags.shift.rawValue)), // only Shift is not a valid hotkey
            (kVK_ANSI_A, 0),                                         // no modifier, and not a function key
            (kVK_Escape, command),                                   // Escape is never a hotkey
        ]
        for kind in HotKeyKind.allCases {
            for values in broken {
                defaults.set(values.code, forKey: kind == .draw ? "drawHotKeyCode" : "clickThroughHotKeyCode")
                defaults.set(values.modifiers, forKey: kind == .draw ? "drawHotKeyModifiers" : "clickThroughHotKeyModifiers")
                #expect(store.hotKey(kind) == kind.startValue, "\(kind) \(values)")
            }
        }
        #expect(store.hotKey(.draw) == controlOptionD)
        #expect(store.hotKey(.clickThrough) == controlOptionC)

        defaults.set(["x"], forKey: "loginItemWasTried")
        #expect(store.loginItemWasTried == false)
    }

    /// Rows 5.4 and 5.7: the same key for the two hotkeys is not a valid stored pair.
    @Test func row5_7_theSameStoredKeyForTheTwoHotKeysGivesTheStartValues() {
        let store = SettingsStore(defaults: MemoryDefaults())
        let commandF6 = HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: .command)
        store.setHotKey(commandF6, for: .draw)
        store.setHotKey(commandF6, for: .clickThrough)
        #expect(store.hotKey(.draw) == controlOptionD)
        #expect(store.hotKey(.clickThrough) == controlOptionC)

        // The draw hotkey has the start value of the other one, and the other one has no stored value.
        let second = SettingsStore(defaults: MemoryDefaults())
        second.setHotKey(controlOptionC, for: .draw)
        #expect(second.hotKey(.draw) == controlOptionD)
        #expect(second.hotKey(.clickThrough) == controlOptionC)
    }

    @Test func row5_10_theFirstStartSetsAPositionForTheMenuBarIcon() {
        let defaults = MemoryDefaults()
        #expect(SettingsStore.statusItemPositionKey(autosaveName: "YaseenScreendraw") == positionKey)
        #expect(defaults.object(forKey: positionKey) == nil)

        SettingsStore(defaults: defaults).setFirstStatusItemPosition(autosaveName: "YaseenScreendraw")
        #expect(defaults.object(forKey: positionKey) as? Double == 460)
        // Only this key is written.
        #expect(defaults.object(forKey: "NSStatusItem Preferred Position Item-0") == nil)
    }

    @Test func row5_10_aPositionThatExistsDoesNotChange() {
        // The user moved the icon: macOS wrote a number. A value of a different type also stays.
        for existing in [404.0, 0.0, 460.5, "left", 12] as [Any] {
            let defaults = MemoryDefaults()
            defaults.set(existing, forKey: positionKey)
            let store = SettingsStore(defaults: defaults)
            store.setFirstStatusItemPosition(autosaveName: "YaseenScreendraw")
            store.setFirstStatusItemPosition(autosaveName: "YaseenScreendraw")
            #expect(String(describing: defaults.object(forKey: positionKey)) == String(describing: Optional(existing)))
        }
    }
}
