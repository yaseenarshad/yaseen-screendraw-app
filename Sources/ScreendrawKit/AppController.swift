import AppKit
import os

/// The app shell: it starts the app and connects the two hotkeys and the menu to the drawing part.
///
/// The shell knows the drawing part only as a `DrawControlling`.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    /// What "Settings…" does. The default opens the settings window.
    public lazy var openSettings: () -> Void = { [weak self] in self?.showSettingsWindow() }

    let statusMenu = StatusMenu()
    let settings: SettingsModel

    private let draw: DrawControlling
    private let store: SettingsStore
    private let hotKeys: HotKeyRegistering
    private let log = Logger(subsystem: "com.yaseenarshad.yaseenscreendraw", category: "shell")
    private var settingsWindow: SettingsWindowController?

    public init(draw: DrawControlling, store: SettingsStore, hotKeys: HotKeyRegistering, loginItem: LoginItem) {
        self.draw = draw
        self.store = store
        self.hotKeys = hotKeys
        settings = SettingsModel(store: store, hotKeys: hotKeys, loginItem: loginItem)
    }

    /// Starts the app with the real drawing part, the real hotkeys and the stored settings. It does not return.
    public nonisolated static func main() {
        // `main.swift` runs on the main thread, but the compiler does not know that in Swift 5 mode.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let controller = AppController(
                draw: DrawController(defaults: .standard),
                store: SettingsStore(defaults: .standard),
                hotKeys: HotKeyCenter(),
                loginItem: SystemLoginItem()
            )
            app.delegate = controller
            // The same as `LSUIElement`: no Dock icon, also when the binary runs outside the bundle.
            app.setActivationPolicy(.accessory)
            // The delegate of the app is a weak reference.
            withExtendedLifetime(controller) { app.run() }
        }
    }

    // MARK: The life of the app

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // The binary has no bundle identifier when it runs outside the bundle. Then there is no check.
        if let identifier = Bundle.main.bundleIdentifier {
            let copies = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            let own = ProcessInfo.processInfo.processIdentifier
            if AppController.isSecondCopy(own: own, running: copies.map(\.processIdentifier)) {
                NSApp.terminate(nil)
                return
            }
        }
        start()
        statusMenu.showInMenuBar()
    }

    /// The app lives in the menu bar. To close the settings window does not quit it.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// True when a different process of this app runs. Then this copy quits at once (row 1.2).
    static func isSecondCopy(own: pid_t, running: [pid_t]) -> Bool {
        running.contains { $0 != own }
    }

    /// Connects the hotkeys, the menu and the drawing part. It shows nothing on the screen.
    func start() {
        // Before the status item exists: macOS reads the position when it makes the item (row 5.10).
        store.setFirstStatusItemPosition(autosaveName: StatusMenu.autosaveName)

        statusMenu.onToggleDrawing = { [weak self] in self?.draw.toggleDrawing() }
        statusMenu.onToggleClickThrough = { [weak self] in self?.draw.toggleClickThrough() }
        statusMenu.onClearAll = { [weak self] in self?.draw.clearAll() }
        statusMenu.onOpenSettings = { [weak self] in self?.openSettings() }
        statusMenu.onQuit = { NSApp.terminate(nil) }
        for kind in HotKeyKind.allCases { statusMenu.showHotKey(settings.hotKey(kind), for: kind) }
        settings.onHotKeyChanged = { [weak self] kind, hotKey in self?.statusMenu.showHotKey(hotKey, for: kind) }

        // The menu titles, the rows that are available, and the menu bar symbol follow the mode.
        draw.onModeChange = { [weak self] mode in self?.statusMenu.show(mode) }
        statusMenu.show(draw.mode)

        hotKeys.onHotKey = { [weak self] kind in
            // macOS calls this on the main thread.
            MainActor.assumeIsolated {
                switch kind {
                case .draw: self?.draw.toggleDrawing()
                case .clickThrough: self?.draw.toggleClickThrough()
                }
            }
        }
        // The app continues to run when macOS refuses a hotkey. The menu still changes the mode,
        // and the settings window shows the red line (row 5.5).
        settings.registerHotKeys()
        for kind in HotKeyKind.allCases where settings.hotKeyProblem(kind) != nil {
            log.error("macOS refused the hotkey \(self.settings.hotKey(kind).text, privacy: .public). A different app can have it.")
        }
        settings.registerLoginItemAtFirstStart()
    }

    // MARK: The settings window

    private func showSettingsWindow() {
        // One window for the life of the app. A second "Settings…" shows the same window (row 5.1).
        let window = settingsWindow ?? SettingsWindowController(model: settings)
        settingsWindow = window
        window.show()
    }
}
