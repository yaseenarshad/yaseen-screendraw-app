import CoreGraphics
import Foundation

/// Where the user put the toolbar (D16): its screen, its place on that screen, and its form.
struct ToolbarPlace: Equatable {
    let displayID: CGDirectDisplayID
    /// The bottom-left corner of the toolbar, from the bottom-left corner of its screen.
    let origin: CGPoint
    let form: ToolbarForm
}

/// The small values that the drawing part remembers: the tool, the size, the colour, the stay
/// mode, and the place of the toolbar. Nothing else of the drawing part goes to the disk. No mark is saved.
///
/// The `UserDefaults` is a parameter, so a test gives one that keeps its values in memory.
/// A value that is missing or broken gives the value of the first start. The store never fails.
/// The settings of the shell (the hotkeys) are in `SettingsStore`. The two share no key.
struct DrawPrefs {
    private enum Key {
        static let tool = "drawTool"
        static let size = "drawSize"
        static let color = "drawColor"
        static let stay = "drawStayMode"
        static let toolbarPlace = "toolbarPlace"
    }

    let defaults: UserDefaults

    /// The first start: Pen (D5).
    var tool: Tool {
        get { read(Key.tool) ?? .pen }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.tool) }
    }

    /// The first start: Thick (D5).
    var size: MarkSize {
        get { read(Key.size) ?? .thick }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.size) }
    }

    /// The first start: red (D5).
    var color: MarkColor {
        get { read(Key.color) ?? .red }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.color) }
    }

    /// The first start: Sticky (D6).
    var stay: StayMode {
        get { read(Key.stay) ?? .sticky }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.stay) }
    }

    /// The place that the user gave the toolbar with a drag (row 2.107). `nil` before the first
    /// drag, and for a value that is broken. The user of the place checks it against the screens.
    var toolbarPlace: ToolbarPlace? {
        get {
            guard let stored = defaults.object(forKey: Key.toolbarPlace) as? [String: Any],
                  let display = (stored["display"] as? Int).flatMap({ CGDirectDisplayID(exactly: $0) }),
                  let x = stored["x"] as? Double, let y = stored["y"] as? Double,
                  let form = (stored["form"] as? String).flatMap(ToolbarForm.init(rawValue:))
            else { return nil }
            return ToolbarPlace(displayID: display, origin: CGPoint(x: x, y: y), form: form)
        }
        nonmutating set {
            guard let place = newValue else {
                defaults.removeObject(forKey: Key.toolbarPlace)
                return
            }
            defaults.set([
                "display": Int(place.displayID), "x": Double(place.origin.x), "y": Double(place.origin.y),
                "form": place.form.rawValue,
            ] as [String: Any], forKey: Key.toolbarPlace)
        }
    }

    private func read<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        (defaults.object(forKey: key) as? String).flatMap(Value.init(rawValue:))
    }
}
