import Foundation

/// The four small values that the drawing part remembers: the tool, the size, the colour and
/// the stay mode. Nothing else of the drawing part goes to the disk. No mark is saved.
///
/// The `UserDefaults` is a parameter, so a test uses its own suite and removes it after.
/// A value that is missing or broken gives the value of the first start. The store never fails.
struct DrawPrefs {
    private enum Key {
        static let tool = "drawTool"
        static let size = "drawSize"
        static let color = "drawColor"
        static let stay = "drawStayMode"
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

    private func read<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        (defaults.object(forKey: key) as? String).flatMap(Value.init(rawValue:))
    }
}
