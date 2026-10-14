import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The rows of the settings window (D7, D11): the two hotkeys, "Open at login", and the keys of the toolbar.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                hotKeyRow("Draw on / off", .draw)
                hotKeyRow("Click through", .clickThrough)
                openAtLoginRow
            }
            Section("Toolbar keys") {
                toolbarKeys
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var openAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at login", isOn: Binding(
                get: { model.openAtLogin },
                set: { model.setOpenAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!model.loginItemIsAvailable)

            if let note = model.loginItemNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if let problem = model.loginItemProblem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
        }
    }

    /// The recorder of one hotkey: "Change…" starts it, and the same button stops it.
    /// The window controller gives the keys to the model while the row records.
    private func hotKeyRow(_ title: String, _ kind: HotKeyKind) -> some View {
        let isRecording = (model.recording == kind)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack {
                    Text(isRecording ? "Type a hotkey" : model.hotKey(kind).text)
                        .foregroundStyle(isRecording ? .secondary : .primary)
                    Button(isRecording ? "Cancel" : "Change…") {
                        if isRecording {
                            model.cancelRecording()
                        } else {
                            model.startRecording(kind)
                        }
                    }
                }
            }
            if let problem = model.hotKeyProblem(kind) {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
        }
    }

    // MARK: The keys of the toolbar

    /// The 18 keys in four groups, three in a line, so the window stays low (rows 5.20 and 5.27).
    private var toolbarKeys: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ToolbarAction.groups, id: \.title) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    VStack(spacing: 6) {
                        ForEach(SettingsView.lines(of: group.actions), id: \.self) { line in
                            HStack(spacing: 10) {
                                ForEach(line, id: \.self) { toolbarKeyCell($0) }
                            }
                        }
                    }
                }
            }
            if let problem = model.toolbarKeyProblem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Text(toolbarKeyNote).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to the start keys") { model.resetToolbarKeys() }
            }
        }
    }

    private var toolbarKeyNote: String {
        if let action = model.recordingToolbarKey {
            return "Type the new key for \(action.name). Esc stops."
        }
        return "Click a key, then type the new key."
    }

    /// The recorder of one toolbar key: a click on the key starts it, and a second click stops it.
    /// The window controller gives the keys to the model while the key records.
    private func toolbarKeyCell(_ action: ToolbarAction) -> some View {
        let isRecording = (model.recordingToolbarKey == action)
        let key = model.toolbarKey(action).uppercased()
        return HStack(spacing: 4) {
            Text(action.name).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            Button {
                if isRecording {
                    model.cancelRecording()
                } else {
                    model.startRecordingToolbarKey(action)
                }
            } label: {
                Text(isRecording ? "…" : key).frame(width: 18)
            }
            .controlSize(.small)
            .accessibilityLabel("The key of \(action.name): \(key)")
        }
        .frame(maxWidth: .infinity)
    }

    private static func lines(of actions: [ToolbarAction]) -> [[ToolbarAction]] {
        stride(from: 0, to: actions.count, by: 3).map { Array(actions[$0..<min($0 + 3, actions.count)]) }
    }
}

/// The one settings window of the app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    let window: NSPanel
    /// Exists only while the settings window has the keyboard.
    private(set) var keyMonitor: Any?

    init(model: SettingsModel) {
        self.model = model
        // A panel that does not activate the app. The app is an accessory app, and macOS can refuse
        // to make it the active app. A normal window then opens with no keyboard, and it goes behind
        // the windows of the active app (YAZ-2823). This panel takes the keyboard without the active app.
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        // It stays above the other windows until the user closes it, so it cannot get lost.
        window.isFloatingPanel = true
        window.title = "Yaseen Screendraw settings"
        // The controller keeps the window, so "Settings…" shows the same window again.
        window.isReleasedWhenClosed = false
        window.delegate = self

        let host = NSHostingController(rootView: SettingsView(model: model))
        // The window follows the height of the form: a red line adds a row.
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.center()
    }

    deinit {
        if let keyMonitor = keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// Shows the window in front of other apps and gives it the keyboard. A second call shows the same window.
    func show() {
        model.refreshOpenAtLogin()
        // `orderFrontRegardless` does not need the active app, and a panel that does not activate
        // the app can take the keyboard without it.
        window.orderFrontRegardless()
        window.makeKey()
    }

    // MARK: The keys

    /// A monitor sees a key before the window does. Thus the recorder also gets a combination with Command,
    /// which the window would handle as a key equivalent.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only plain values cross into the main actor: `NSEvent` is not `Sendable`.
            guard let combo = HotKeyCombo(keyDown: event) else { return event }
            // A toolbar key is the character that the key types, not the position of the key (row 2.39).
            let characters = event.charactersIgnoringModifiers
            let windowNumber = event.windowNumber
            let used = MainActor.assumeIsolated {
                self?.keyDown(combo, characters: characters, windowNumber: windowNumber) ?? false
            }
            // `nil` tells AppKit that the key is used.
            return used ? nil : event
        }
    }

    /// The keys of the overlay (Esc, Undo, the typing of a text) must not go through a monitor of this window.
    private func stopKeyMonitor() {
        if let keyMonitor = keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns `true` when the key is used.
    private func keyDown(_ combo: HotKeyCombo, characters: String?, windowNumber: Int) -> Bool {
        guard windowNumber == window.windowNumber else { return false }
        if model.keyDown(combo, characters: characters) { return true }
        // The app has no main menu, so nothing else gives Command-W to the window.
        if combo == HotKeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: .command) {
            window.performClose(nil)
            return true
        }
        return false
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // The user can come back from System Settings, Login Items.
        model.refreshOpenAtLogin()
        startKeyMonitor()
    }

    // A recorder must not stay open with the two global hotkeys off.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
        stopKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
        stopKeyMonitor()
    }
}
