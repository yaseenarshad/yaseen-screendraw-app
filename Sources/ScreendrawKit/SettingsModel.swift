import AppKit
import Carbon.HIToolbox

/// The state and the rules of the settings window, with no window and no view.
///
/// The model owns the changes of the settings: it registers the two hotkeys, stores them,
/// and asks macOS for "open at login". The app and the window only call it. Thus a test proves the rules.
@MainActor
final class SettingsModel: ObservableObject {
    static let needsModifierText = "A hotkey needs ⌘, ⌃ or ⌥ with the key, or a function key."
    static let sameKeyText = "The two hotkeys must be different."
    static let refusedText = "macOS refused this hotkey. A different app can have it."
    static let loginItemNotAvailableText = "Open at login works only in the installed app."
    static let loginItemNotChangedText = "macOS did not change this setting. Look at Login Items in System Settings."

    @Published private var combos: [HotKeyKind: HotKeyCombo]
    /// The hotkey whose row waits for a key. The two global hotkeys are off during that time.
    @Published private(set) var recording: HotKeyKind?
    /// The red line below the row of a hotkey.
    @Published private var hotKeyProblems: [HotKeyKind: String] = [:]
    /// The real state from macOS, not a stored value.
    @Published private(set) var openAtLogin = false
    /// The red line below the switch.
    @Published private(set) var loginItemProblem: String?

    /// The menu shows the two hotkeys, so the app must know each change.
    var onHotKeyChanged: (HotKeyKind, HotKeyCombo) -> Void = { _, _ in }

    private let store: SettingsStore
    private let hotKeys: HotKeyRegistering
    private let loginItem: LoginItem

    init(store: SettingsStore, hotKeys: HotKeyRegistering, loginItem: LoginItem) {
        self.store = store
        self.hotKeys = hotKeys
        self.loginItem = loginItem
        combos = [.draw: store.hotKey(.draw), .clickThrough: store.hotKey(.clickThrough)]
        refreshOpenAtLogin()
    }

    // MARK: The two hotkeys

    func hotKey(_ kind: HotKeyKind) -> HotKeyCombo {
        combos[kind] ?? kind.startValue
    }

    func hotKeyProblem(_ kind: HotKeyKind) -> String? {
        hotKeyProblems[kind]
    }

    /// Registers the two hotkeys. The app calls this at the start.
    /// When macOS refuses one, the app continues to run and the window shows the red line.
    func registerHotKeys() {
        for kind in HotKeyKind.allCases { register(kind) }
    }

    private func register(_ kind: HotKeyKind) {
        hotKeyProblems[kind] = hotKeys.register(hotKey(kind), for: kind) ? nil : SettingsModel.refusedText
    }

    /// "Change…" of one row.
    func startRecording(_ kind: HotKeyKind) {
        guard recording != kind else { return }
        // With the hotkeys still registered, macOS would change the mode and the row would not get the key.
        // Thus the user can also record a key that is a hotkey now (row 5.6).
        for each in HotKeyKind.allCases { hotKeys.unregister(each) }
        // A new try starts with no old message.
        hotKeyProblems = [:]
        recording = kind
    }

    /// Stops the recorder with no change. The two hotkeys work again.
    func cancelRecording() {
        guard recording != nil else { return }
        recording = nil
        registerHotKeys()
    }

    /// A key-down in the settings window. Returns `true` when the model used the key.
    func keyDown(_ combo: HotKeyCombo) -> Bool {
        guard let kind = recording else { return false }
        if combo.keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return true
        }

        recording = nil
        let reason = refusal(of: combo, for: kind)
        if reason == nil, hotKeys.register(combo, for: kind) {
            // Store only a combination that macOS accepted. It works at once (row 5.2).
            combos[kind] = combo
            store.setHotKey(combo, for: kind)
            hotKeyProblems[kind] = nil
            onHotKeyChanged(kind, combo)
        } else {
            // The old hotkey stays, and the red line tells why (rows 5.3, 5.4, 5.5).
            register(kind)
            hotKeyProblems[kind] = reason ?? SettingsModel.refusedText
        }
        // The recorder stopped the other hotkey too.
        register(kind.other)
        return true
    }

    /// Why the app itself refuses the combination. `nil` when only macOS can still refuse it.
    private func refusal(of combo: HotKeyCombo, for kind: HotKeyKind) -> String? {
        if !combo.isValid { return SettingsModel.needsModifierText }
        if combo == hotKey(kind.other) { return SettingsModel.sameKeyText }
        return nil
    }

    // MARK: Open at login

    var loginItemIsAvailable: Bool { loginItem.isAvailable }

    /// The grey line below the switch.
    var loginItemNote: String? {
        loginItem.isAvailable ? nil : SettingsModel.loginItemNotAvailableText
    }

    /// Reads the real state again. The user can change it in System Settings while the app runs.
    func refreshOpenAtLogin() {
        openAtLogin = loginItem.isAvailable && loginItem.isEnabled
    }

    /// The first start turns "Open at login" on one time (row 5.8).
    /// Safe to call at each start: after the first call it does nothing.
    func registerLoginItemAtFirstStart() {
        // Outside the bundle there is nothing to register. Do not use up the one try there.
        guard loginItem.isAvailable, !store.loginItemWasTried else { return }
        store.loginItemWasTried = true
        if !loginItem.isEnabled { setOpenAtLogin(true) }
    }

    /// The switch. When macOS refuses the change, the switch goes back and the red line shows the reason.
    func setOpenAtLogin(_ enabled: Bool) {
        guard loginItem.isAvailable else { return }
        do {
            try loginItem.setEnabled(enabled)
            loginItemProblem = nil
        } catch {
            loginItemProblem = error.localizedDescription
        }
        refreshOpenAtLogin()
        if openAtLogin != enabled, loginItemProblem == nil {
            // macOS gave no error but the state is not the new one (for example, the user must approve the app).
            loginItemProblem = SettingsModel.loginItemNotChangedText
        }
    }
}
