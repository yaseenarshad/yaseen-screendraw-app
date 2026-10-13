import AppKit

/// A screen, as the windows know it. A test gives fixed screens.
struct OverlayScreen: Equatable {
    let display: DrawDisplay
    /// The frame in the global points of AppKit: the origin is at the bottom-left.
    let frame: CGRect
    /// The frame with no menu bar and no Dock.
    let visibleFrame: CGRect
    let scale: CGFloat

    /// The screens of the Mac now.
    static var current: [OverlayScreen] {
        NSScreen.screens.compactMap { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            guard let id = number?.uint32Value else { return nil }
            return OverlayScreen(
                display: DrawDisplay(id: id, size: screen.frame.size),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scale: screen.backingScaleFactor
            )
        }
    }
}

/// The transparent borderless panel that covers one screen while drawing is on (D2).
///
/// It is a panel that does not activate the app. Such a panel takes the keyboard while the app
/// below stays the active app. Then Esc, Undo and the typing of a text arrive here, and the
/// screen below does not change.
final class OverlayWindow: NSPanel {
    /// One below `.screenSaver`: above a full-screen app, the menu bar and the Dock, and below
    /// the freeze of Yaseen Screenshot. Thus a screenshot shows the marks.
    static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    /// On every Space, and above a full-screen app.
    static let allSpaces: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let overlayView: OverlayView

    init(screen: OverlayScreen, session: DrawSession) {
        overlayView = OverlayView(display: screen.display, scale: screen.scale, session: session)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        collectionBehavior = OverlayWindow.allSpaces
        // macOS sends a click on a clear pixel of a transparent window to the window below, until
        // the app sets this value. The overlay must get each click, also where no mark is.
        // The two steps make sure that the value goes to macOS.
        ignoresMouseEvents = true
        ignoresMouseEvents = false
        // A panel takes the keyboard only for a text field, and hides when its app is not active.
        // The overlay needs the keyboard at once, and it must stay.
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isFloatingPanel = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = overlayView
        // Each window sends its keys to its view, also the window that gets the keyboard after a click.
        initialFirstResponder = overlayView
        makeFirstResponder(overlayView)
        // `isFloatingPanel` changes the level, so the level is set after it.
        level = OverlayWindow.overlayLevel
        setFrame(screen.frame, display: false)
    }

    // A borderless window refuses the keyboard by default. The overlay needs Esc and the typing.
    // In click-through it ignores the mouse, and then it must not take the keyboard.
    override var canBecomeKey: Bool { !ignoresMouseEvents }
}
