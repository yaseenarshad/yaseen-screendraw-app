import Foundation

/// The three modes of the app (D4).
///
/// - `off`: no overlay window exists. The screen works as usual.
/// - `drawing`: the overlay takes the mouse and the keyboard.
/// - `clickThrough`: the marks stay, and the mouse and the keyboard go to the apps below.
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

    /// The click-through hotkey and its menu row. It does nothing when the mode is `off`.
    func toggleClickThrough()

    /// The menu row "Clear all". One Undo brings the marks back.
    func clearAll()
}
