import AppKit

/// The settings of the app (D7), in `UserDefaults`.
///
/// The `UserDefaults` is a parameter, so a test uses its own one.
/// A value that is missing or broken gives the start value. The store never fails.
public final class SettingsStore {
    /// The start position of the menu bar icon: the distance from the right edge of the screen in points.
    /// It is on the visible side of the notch of the built-in display (row 5.10).
    public static let firstStatusItemPosition = 460.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: The two hotkeys

    /// The hotkey of this kind. The start value is Control-Option-D or Control-Option-C (row 5.7).
    public func hotKey(_ kind: HotKeyKind) -> HotKeyCombo {
        let combo = storedHotKey(kind)
        // The two hotkeys must be different (row 5.4). A stored pair that is not gives the start values.
        return combo == storedHotKey(kind.other) ? kind.startValue : combo
    }

    public func setHotKey(_ combo: HotKeyCombo, for kind: HotKeyKind) {
        defaults.set(Int(combo.keyCode), forKey: codeKey(kind))
        defaults.set(Int(combo.modifiers.rawValue), forKey: modifiersKey(kind))
    }

    private func storedHotKey(_ kind: HotKeyKind) -> HotKeyCombo {
        guard
            let code = defaults.object(forKey: codeKey(kind)) as? Int,
            let modifiers = defaults.object(forKey: modifiersKey(kind)) as? Int,
            // A virtual key code is one byte.
            (0...0xFF).contains(code), modifiers >= 0
        else { return kind.startValue }
        let combo = HotKeyCombo(
            keyCode: UInt32(code),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        )
        return combo.isValid ? combo : kind.startValue
    }

    private func codeKey(_ kind: HotKeyKind) -> String { name(kind) + "HotKeyCode" }
    private func modifiersKey(_ kind: HotKeyKind) -> String { name(kind) + "HotKeyModifiers" }

    private func name(_ kind: HotKeyKind) -> String {
        switch kind {
        case .draw: return "draw"
        case .clickThrough: return "clickThrough"
        }
    }

    // MARK: Open at login

    /// True after the first start tried to register the app as a login item. The app tries one time only.
    /// The state of "Open at login" is not here: it is in macOS (`LoginItem.isEnabled`).
    public var loginItemWasTried: Bool {
        get { defaults.object(forKey: "loginItemWasTried") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "loginItemWasTried") }
    }

    // MARK: The position of the menu bar icon

    /// The key that macOS reads for the position of the status item with this `autosaveName`.
    public static func statusItemPositionKey(autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// macOS puts a new status item at the left end of the status items. With a full menu bar,
    /// that place is behind the notch, and the user cannot see the icon (YAZ-2768).
    /// So the app sets a position before it makes the status item, but only when no position exists.
    /// A user who moved the icon keeps his place.
    public func setFirstStatusItemPosition(autosaveName: String) {
        let key = SettingsStore.statusItemPositionKey(autosaveName: autosaveName)
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(SettingsStore.firstStatusItemPosition, forKey: key)
    }
}
