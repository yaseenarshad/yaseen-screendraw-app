import Foundation

/// The three modes of the app (D4).
///
/// - `off`: no overlay window exists. The screen works as usual.
/// - `drawing`: the overlay takes the mouse and the keyboard.
/// - `clickThrough`: the pen is paused. The toolbar stays, and the mouse and the keyboard go to
///   the apps below. The marks stay on the screen, or they are hidden until the mode is drawing (D20).
enum DrawMode: Equatable {
    case off, drawing, clickThrough
}

/// What the app shell (the hotkeys and the menu) needs from the drawing part.
///
/// The shell does not know the overlay, the marks, or the toolbar.
@MainActor
protocol DrawControlling: AnyObject {
    var mode: DrawMode { get }

    /// The drawing part calls this on the main thread after each change of `mode`.
    var onModeChange: (DrawMode) -> Void { get set }

    /// The draw hotkey, its menu row, and the Close button.
    func toggleDrawing()

    /// The click-through hotkey and its menu row. When the mode is `off`, it shows the toolbar
    /// with the pen paused (D18).
    func toggleClickThrough()

    /// The menu row "Clear all". One Undo brings the marks back.
    func clearAll()

    /// The gear button of the toolbar, and Command-comma in mode drawing (D13). The drawing part
    /// pauses the pen first, and then calls this. The shell sets it to what "Settings…" does.
    var onOpenSettings: () -> Void { get set }
}
