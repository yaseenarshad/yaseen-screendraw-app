import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The rows of the settings window (D7): the two hotkeys and "Open at login".
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            hotKeyRow("Draw on / off", .draw)
            hotKeyRow("Click through", .clickThrough)

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
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The recorder of one hotkey: "Change…" starts it, and the same button stops it.
    /// The window controller gives the keys to the model while the row records.
    private func hotKeyRow(_ title: String, _ kind: HotKeyKind) -> some View {
        let isRecording = (model.recording == kind)
        return LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
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
                if let problem = model.hotKeyProblem(kind) {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
            }
        }
    }
}

/// The one settings window of the app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let window: NSWindow
    private var keyMonitor: Any?

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.title = "Yaseen Screendraw settings"
        // The controller keeps the window, so "Settings…" shows the same window again.
        window.isReleasedWhenClosed = false
        window.delegate = self

        let host = NSHostingController(rootView: SettingsView(model: model))
        // The window follows the height of the form: a red line adds a row.
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.center()

        // A monitor sees a key before the window does. Thus the recorder also gets a combination with Command,
        // which the window would handle as a key equivalent.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only plain values cross into the main actor: `NSEvent` is not `Sendable`.
            guard let combo = HotKeyCombo(keyDown: event) else { return event }
            let windowNumber = event.windowNumber
            let used = MainActor.assumeIsolated { self?.keyDown(combo, windowNumber: windowNumber) ?? false }
            // `nil` tells AppKit that the key is used.
            return used ? nil : event
        }
    }

    deinit {
        if let keyMonitor = keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// Shows the window in front of other apps. A second call shows the same window.
    func show() {
        model.refreshOpenAtLogin()
        // An accessory app is not active by default. Without this, the window opens behind other apps.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Returns `true` when the key is used.
    private func keyDown(_ combo: HotKeyCombo, windowNumber: Int) -> Bool {
        guard windowNumber == window.windowNumber else { return false }
        if model.keyDown(combo) { return true }
        // The app has no main menu, so nothing else gives Command-W to the window.
        if combo == HotKeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: .command) {
            window.performClose(nil)
            return true
        }
        return false
    }

    // MARK: NSWindowDelegate

    // A recorder must not stay open with the two global hotkeys off.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The user can come back from System Settings, Login Items.
        model.refreshOpenAtLogin()
    }
}
