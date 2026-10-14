import CoreGraphics
import Foundation

/// Where the user put the toolbar (D16): its screen, its place on that screen, and its form.
struct ToolbarPlace: Equatable {
    let displayID: CGDirectDisplayID
    /// The bottom-left corner of the toolbar, from the bottom-left corner of its screen.
    let origin: CGPoint
    let form: ToolbarForm
}

extension DrawPrefs {
    private static let toolbarPlaceKey = "toolbarPlace"

    /// The place that the user gave the toolbar with a drag (row 2.107). `nil` before the first
    /// drag, and for a value that is broken. The user of the place checks it against the screens.
    /// The app writes it only at the end of a drag. No mark and no other value is in it.
    var toolbarPlace: ToolbarPlace? {
        get {
            guard let stored = defaults.object(forKey: DrawPrefs.toolbarPlaceKey) as? [String: Any],
                  let display = (stored["display"] as? Int).flatMap({ CGDirectDisplayID(exactly: $0) }),
                  let x = stored["x"] as? Double, let y = stored["y"] as? Double,
                  let form = (stored["form"] as? String).flatMap(ToolbarForm.init(rawValue:))
            else { return nil }
            return ToolbarPlace(displayID: display, origin: CGPoint(x: x, y: y), form: form)
        }
        nonmutating set {
            guard let place = newValue else {
                defaults.removeObject(forKey: DrawPrefs.toolbarPlaceKey)
                return
            }
            defaults.set([
                "display": Int(place.displayID), "x": Double(place.origin.x), "y": Double(place.origin.y),
                "form": place.form.rawValue,
            ] as [String: Any], forKey: DrawPrefs.toolbarPlaceKey)
        }
    }
}
