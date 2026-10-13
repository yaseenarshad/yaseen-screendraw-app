import AppKit

/// The app shell: it starts the app and connects the hotkeys and the menu to the drawing part.
///
/// This file is a placeholder. Subissue 5 and the shell part of subissue 1 replace it.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private let draw: DrawControlling = DrawController()

    /// Starts the app. It does not return.
    public nonisolated static func main() {
        // `main.swift` runs on the main thread, but the compiler does not know that in Swift 5 mode.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let controller = AppController()
            app.delegate = controller
            // The same as `LSUIElement`: no Dock icon, also when the binary runs outside the bundle.
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
