import AppKit

/// The app shell: it starts the app and connects the hotkeys and the menu to the drawing part.
///
/// This file is a placeholder. Subissue 5 and the shell part of subissue 1 replace it.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private let draw: DrawControlling = DrawController()

    public static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        // A menu bar app: no Dock icon and no main menu.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
