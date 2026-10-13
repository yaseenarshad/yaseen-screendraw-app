import Foundation

/// The drawing part of the app: the session, the overlay windows, and the toolbar.
///
/// This file is a placeholder. Subissues 1 to 4 replace it.
@MainActor
public final class DrawController: DrawControlling {
    public private(set) var mode: DrawMode = .off
    public var onModeChange: (DrawMode) -> Void = { _ in }

    public init(defaults: UserDefaults = .standard) {}

    public func toggleDrawing() {
        mode = (mode == .off) ? .drawing : .off
        onModeChange(mode)
    }

    public func toggleClickThrough() {
        guard mode != .off else { return }
        mode = (mode == .drawing) ? .clickThrough : .drawing
        onModeChange(mode)
    }

    public func clearAll() {}
}
