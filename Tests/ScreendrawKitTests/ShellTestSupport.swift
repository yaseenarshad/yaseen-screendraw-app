import AppKit
@testable import ScreendrawKit

// The fakes of the shell tests. Nothing here shows on the screen, takes a real hotkey,
// writes a real setting, or changes the real login item.

/// A `UserDefaults` that keeps its values in memory only.
///
/// A real suite (`UserDefaults(suiteName:)`) is not possible here: macOS writes a file for it in
/// `~/Library/Preferences`, and writes an empty file again some seconds after `removePersistentDomain`.
/// The tests must leave no file.
final class ShellMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        // The name is never used: each call that the shell makes is overridden below.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

/// A hotkey center that takes no real hotkey. It refuses the combinations in `refused`.
final class FakeHotKeyRegistrar: HotKeyRegistering {
    var onHotKey: (HotKeyKind) -> Void = { _ in }
    var refused: [HotKeyCombo] = []
    private(set) var registered: [HotKeyKind: HotKeyCombo] = [:]

    func register(_ combo: HotKeyCombo, for kind: HotKeyKind) -> Bool {
        // The same as `HotKeyCenter`: a refused call leaves no hotkey of this kind.
        registered[kind] = nil
        // macOS also refuses a combination that this app has registered.
        if refused.contains(combo) || registered.values.contains(combo) { return false }
        registered[kind] = combo
        return true
    }

    func unregister(_ kind: HotKeyKind) { registered[kind] = nil }

    /// The user presses these keys. As in macOS, only a registered hotkey tells the app.
    func press(_ combo: HotKeyCombo) {
        for kind in HotKeyKind.allCases where registered[kind] == combo { onHotKey(kind) }
    }
}

/// A login item that never talks to macOS.
final class FakeLoginItem: LoginItem {
    struct Refused: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    var isAvailable = true
    var isEnabled = false
    var refuses = false
    /// macOS gives no error, but the state does not change (the user must approve the app first).
    var ignores = false
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if refuses { throw Refused() }
        if !ignores { isEnabled = enabled }
    }
}

/// A drawing part with no overlay. It changes the mode as D4 tells, and keeps each call.
@MainActor
final class FakeDrawControl: DrawControlling {
    private(set) var mode: DrawMode = .off
    var onModeChange: (DrawMode) -> Void = { _ in }
    private(set) var calls: [String] = []

    func toggleDrawing() {
        calls.append("toggleDrawing")
        set(mode == .off ? .drawing : .off)
    }

    func toggleClickThrough() {
        calls.append("toggleClickThrough")
        guard mode != .off else { return }
        set(mode == .drawing ? .clickThrough : .drawing)
    }

    func clearAll() {
        calls.append("clearAll")
    }

    private func set(_ mode: DrawMode) {
        self.mode = mode
        onModeChange(mode)
    }
}

/// What a click on a menu row does, with no menu on the screen. A row that is not available does nothing.
@MainActor
func click(_ row: NSMenuItem) {
    guard row.isEnabled, let action = row.action else { return }
    _ = row.target?.perform(action, with: row)
}
