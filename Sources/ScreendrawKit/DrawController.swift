import AppKit

/// The drawing part of the app: the session, the overlay windows, the toolbar and the timer.
///
/// `DrawSession` holds all the state. This class is the thin layer for AppKit: it opens and
/// closes the windows for the mode, and it runs the timer while a Fade or Hold mark exists.
/// While the mode is off, no window, no timer and no observer exists. The kept marks are data only.
@MainActor
public final class DrawController: DrawControlling {
    public var mode: DrawMode { session.mode }
    public var onModeChange: (DrawMode) -> Void = { _ in }

    let session: DrawSession
    private let screens: () -> [OverlayScreen]
    private let pointer: () -> CGPoint
    private let showsWindows: Bool
    private var shownMode = DrawMode.off
    private var shownScreens: [OverlayScreen] = []
    /// One for each screen while drawing is on. Empty while the mode is off.
    private(set) var overlays: [OverlayWindow] = []
    private(set) var toolbarPanel: ToolbarPanel?
    /// Exists only while a Fade or Hold mark exists.
    private(set) var timer: Timer?
    /// Exists only while drawing is on.
    private(set) var screenObserver: NSObjectProtocol?

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(
            defaults: defaults,
            now: { ProcessInfo.processInfo.systemUptime },
            screens: { OverlayScreen.current },
            pointer: { NSEvent.mouseLocation },
            showsWindows: true
        )
    }

    /// A test gives a clock that it sets, fixed screens and a fixed pointer, and `showsWindows: false`.
    /// Then the windows are made, but none is put on the screen.
    init(
        defaults: UserDefaults,
        now: @escaping () -> TimeInterval,
        screens: @escaping () -> [OverlayScreen],
        pointer: @escaping () -> CGPoint,
        showsWindows: Bool
    ) {
        session = DrawSession(prefs: DrawPrefs(defaults: defaults), now: now)
        self.screens = screens
        self.pointer = pointer
        self.showsWindows = showsWindows
        session.onChange = { [weak self] in self?.sessionChanged() }
    }

    // MARK: What the shell calls

    public func toggleDrawing() {
        if session.mode == .off {
            shownScreens = screens()
            session.start(displays: shownScreens.map { $0.display })
        } else {
            session.stop()
        }
    }

    public func toggleClickThrough() {
        session.toggleClickThrough()
    }

    public func clearAll() {
        session.clearAll()
    }

    // MARK: The session changed

    private func sessionChanged() {
        let modeChanged = session.mode != shownMode
        if modeChanged {
            let previous = shownMode
            shownMode = session.mode
            if shownMode == .off {
                closeWindows()
            } else {
                if previous == .off { openWindows() }
                showMode()
            }
        }
        overlays.forEach { $0.overlayView.refresh() }
        toolbarPanel?.toolbarView.refresh()
        updateTimer()
        if modeChanged { onModeChange(shownMode) }
    }

    // MARK: The windows

    /// No window goes on the screen outside the run loop of the app. A test has no run loop, so
    /// a test can never put a window on the screen.
    private var canShow: Bool {
        showsWindows && NSApplication.shared.isRunning
    }

    /// The screen that has the pointer.
    private var pointerScreen: OverlayScreen? {
        let point = pointer()
        return shownScreens.first { $0.frame.contains(point) } ?? shownScreens.first
    }

    /// The toolbar and the observer of the screens. `showMode` makes the overlays.
    private func openWindows() {
        let panel = ToolbarPanel(session: session)
        moveToBottomCentre(panel)
        toolbarPanel = panel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// The toolbar shows at the bottom centre of the screen that has the pointer.
    private func moveToBottomCentre(_ panel: ToolbarPanel) {
        guard let screen = pointerScreen else { return }
        panel.setFrameOrigin(Toolbar.origin(for: panel.frame.size, on: screen.visibleFrame))
    }

    /// Drawing or click-through: who gets the mouse and the keyboard.
    ///
    /// Each mode gets new overlay windows. A window that starts to ignore the mouse and leaves
    /// the screen in the same moment can keep the mouse. Then the clicks do not go to the apps.
    /// A window that ignores the mouse from its start does not have this problem (YAZ-2792).
    private func showMode() {
        let isClickThrough = shownMode == .clickThrough
        // The dim toolbar tells that the pen is paused. It still takes clicks.
        toolbarPanel?.alphaValue = isClickThrough ? 0.5 : 1
        let old = overlays
        overlays = shownScreens.map { OverlayWindow(screen: $0, session: session, clickThrough: isClickThrough) }
        overlays.forEach { $0.overlayView.refresh() }

        if canShow {
            overlays.forEach { $0.orderFrontRegardless() }
            toolbarPanel?.orderFrontRegardless()
            if !isClickThrough {
                // The overlay below the pointer takes the keyboard. The app below stays the active app.
                let point = pointer()
                (overlays.first { $0.frame.contains(point) } ?? overlays.first)?.makeKey()
                NSCursor.crosshair.set()
            }
        }
        // The old windows close after the new ones are on the screen. Thus the marks do not blink.
        // In click-through, the close of the window that has the keyboard gives the keyboard back
        // to the app below.
        close(old)
    }

    private func closeWindows() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        let closed: [NSWindow] = overlays + (toolbarPanel.map { [$0] } ?? [])
        overlays = []
        toolbarPanel = nil
        shownScreens = []
        close(closed)
        if canShow { NSCursor.arrow.set() }
    }

    private func close(_ windows: [NSWindow]) {
        windows.forEach { $0.close() }
        // AppKit can still be inside an event of one of these windows. Thus the windows go away
        // on the next turn of the run loop.
        DispatchQueue.main.async { withExtendedLifetime(windows) {} }
    }

    /// A monitor was connected or removed while drawing is on: the overlays are made again for
    /// the new set of screens.
    func screensChanged() {
        let newScreens = screens()
        guard shownMode != .off, newScreens != shownScreens else { return }
        shownScreens = newScreens
        session.setDisplays(newScreens.map { $0.display })
        // The toolbar stays where the user put it, unless its screen is gone.
        if let panel = toolbarPanel {
            let middle = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            if !newScreens.contains(where: { $0.frame.contains(middle) }) { moveToBottomCentre(panel) }
        }
        showMode()
    }

    // MARK: The timer

    private func updateTimer() {
        if session.hasTimedMarks, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !session.hasTimedMarks, let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    /// One tick of the timer: the marks that are fully faded go away, and the marks that fade get weaker.
    func tick() {
        session.tick()
        overlays.forEach { $0.overlayView.refreshOpacities() }
    }
}
