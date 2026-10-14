import AppKit
import Carbon.HIToolbox

/// The state and the rules of the settings window, with no window and no view.
///
/// The model owns the changes of the settings: it registers the two hotkeys, stores them, stores
/// the keys of the toolbar, the seconds of Fade and Hold and the switch of Esc, and asks macOS for
/// "open at login". The app and the window only call it.
/// Thus a test proves the rules.
@MainActor
final class SettingsModel: ObservableObject {
    static let needsModifierText = "A hotkey needs ⌘, ⌃ or ⌥ with the key, or a function key."
    static let sameKeyText = "The two hotkeys must be different."
    static let refusedText = "macOS refused this hotkey. A different app can have it."
    static let toolbarKeyNotValidText = "A toolbar key is one letter, digit or punctuation mark, with no ⌘, ⌃ or ⌥."
    static let fadeSecondsNotValidText = "Fade seconds must be a whole number from 1 to 60."
    static let holdSecondsNotValidText = "Hold seconds must be a whole number from 1 to 60."
    static let loginItemNotAvailableText = "Open at login works only in the installed app."
    static let loginItemNotChangedText = "macOS did not change this setting. Look at Login Items in System Settings."

    @Published private var combos: [HotKeyKind: HotKeyCombo]
    /// The hotkey whose row waits for a key. The two global hotkeys are off during that time.
    @Published private(set) var recording: HotKeyKind?
    /// The red line below the row of a hotkey.
    @Published private var hotKeyProblems: [HotKeyKind: String] = [:]
    /// The key of each toolbar action, in lower case.
    @Published private var toolbarKeys: [ToolbarAction: String]
    /// The toolbar action whose key waits for a key. The two global hotkeys are off during that time.
    @Published private(set) var recordingToolbarKey: ToolbarAction?
    /// The red line below the toolbar keys.
    @Published private(set) var toolbarKeyProblem: String?
    /// A Fade mark is gone this many seconds after it is finished (D12).
    @Published private(set) var fadeSeconds: Int
    /// The Hold marks stay this many seconds after the last drawing activity (D12).
    @Published private(set) var holdSeconds: Int
    /// The red line below the two seconds fields.
    @Published private(set) var secondsProblem: String?
    /// The switch "Marks stay visible after Esc" (D20).
    @Published private(set) var marksStayAfterEsc: Bool
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
        toolbarKeys = store.toolbarKeys.all
        fadeSeconds = store.drawPrefs.fadeSeconds
        holdSeconds = store.drawPrefs.holdSeconds
        marksStayAfterEsc = store.drawPrefs.marksStayAfterEsc
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
        pauseHotKeys()
        recordingToolbarKey = nil
        recording = kind
    }

    /// The start of each recorder, of a hotkey or of a toolbar key (rows 5.6 and 5.26).
    private func pauseHotKeys() {
        // With the hotkeys still registered, macOS would change the mode and the row would not get the key.
        // Thus the user can also record a key that is a hotkey now (row 5.6).
        for each in HotKeyKind.allCases { hotKeys.unregister(each) }
        // A new try starts with no old message.
        hotKeyProblems = [:]
        toolbarKeyProblem = nil
    }

    /// Stops the recorder with no change. The two hotkeys work again.
    func cancelRecording() {
        guard recording != nil || recordingToolbarKey != nil else { return }
        recording = nil
        recordingToolbarKey = nil
        registerHotKeys()
    }

    /// A key-down in the settings window. Returns `true` when the model used the key.
    /// `characters` is what the key types, with no Command, Control or Option. Only a toolbar key needs it.
    func keyDown(_ combo: HotKeyCombo, characters: String? = nil) -> Bool {
        guard recording != nil || recordingToolbarKey != nil else { return false }
        if combo.keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return true
        }
        if let action = recordingToolbarKey {
            recordToolbarKey(ToolbarKeys.key(typed: characters, modifiers: combo.modifiers), for: action)
            return true
        }
        guard let kind = recording else { return false }

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

    // MARK: The keys of the toolbar

    func toolbarKey(_ action: ToolbarAction) -> String {
        toolbarKeys[action] ?? action.startKey
    }

    /// A click on the key of one toolbar action. The recorder is the one of the hotkeys: one
    /// row records at a time, and the two global hotkeys are paused (row 5.26).
    func startRecordingToolbarKey(_ action: ToolbarAction) {
        guard recordingToolbarKey != action else { return }
        pauseHotKeys()
        recording = nil
        recordingToolbarKey = action
    }

    /// The recorder got a key. `key` is `nil` when the key press is not a valid toolbar key.
    private func recordToolbarKey(_ key: String?, for action: ToolbarAction) {
        recordingToolbarKey = nil
        if let key = key {
            if let owner = ToolbarAction.all.first(where: { $0 != action && toolbarKey($0) == key }) {
                // The old key stays, and the red line names the action that has the key (row 5.22).
                toolbarKeyProblem = SettingsModel.toolbarKeyTakenText(key, owner: owner)
            } else {
                // The drawing part reads the store when a key arrives, so the key works at once (row 5.23).
                store.toolbarKeys.set(key, for: action)
                toolbarKeys = store.toolbarKeys.all
            }
        } else {
            toolbarKeyProblem = SettingsModel.toolbarKeyNotValidText
        }
        // The recorder paused the two hotkeys.
        registerHotKeys()
    }

    static func toolbarKeyTakenText(_ key: String, owner: ToolbarAction) -> String {
        "The key \(key.uppercased()) belongs to \(owner.name)."
    }

    /// "Reset to the start keys" (row 5.24). The two hotkeys do not change.
    func resetToolbarKeys() {
        cancelRecording()
        store.toolbarKeys.reset()
        toolbarKeys = store.toolbarKeys.all
        toolbarKeyProblem = nil
    }

    // MARK: The seconds of Fade and Hold

    /// The field "Fade seconds" has a new text. A whole number from 1 to 60 is stored, and the
    /// drawing part uses it for the next Fade mark (rows 3.21 and 3.25). Each other text is
    /// refused: the old value stays, and the red line tells the rule (row 3.22).
    func setFadeSeconds(_ text: String) {
        if let seconds = SettingsModel.seconds(from: text) {
            store.drawPrefs.fadeSeconds = seconds
            fadeSeconds = seconds
            secondsProblem = nil
        } else {
            secondsProblem = SettingsModel.fadeSecondsNotValidText
        }
    }

    /// The field "Hold seconds" has a new text. The rules of `setFadeSeconds` apply. The Hold
    /// marks that are on the screen use the new value at once (row 3.25).
    func setHoldSeconds(_ text: String) {
        if let seconds = SettingsModel.seconds(from: text) {
            store.drawPrefs.holdSeconds = seconds
            holdSeconds = seconds
            secondsProblem = nil
        } else {
            secondsProblem = SettingsModel.holdSecondsNotValidText
        }
    }

    /// The whole number from 1 to 60 that a text gives. `nil` for an empty text, 0, 61 or a letter.
    private static func seconds(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces)).flatMap { DrawPrefs.secondsRange.contains($0) ? $0 : nil }
    }

    // MARK: The marks after Esc

    /// The switch "Marks stay visible after Esc" (row 4.36). The drawing part reads the store when
    /// Esc arrives, so the new value works at the next Esc.
    func setMarksStayAfterEsc(_ stay: Bool) {
        store.drawPrefs.marksStayAfterEsc = stay
        marksStayAfterEsc = stay
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
