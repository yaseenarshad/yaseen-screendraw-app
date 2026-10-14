import AppKit
@testable import ScreendrawKit

// The fakes of the shell tests. Nothing here shows on the screen, takes a real hotkey,
// or changes the real login item. The settings of a test are a `MemoryDefaults`.

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
    var onOpenSettings: () -> Void = {}
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
