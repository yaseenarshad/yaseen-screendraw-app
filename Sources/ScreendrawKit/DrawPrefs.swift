import Foundation

/// The small values that the drawing part remembers: the tool, the size, the colour, the stay
/// mode, and the seconds of Fade and Hold. Nothing else of the drawing part goes to the disk.
/// No mark is saved.
///
/// The `UserDefaults` is a parameter, so a test gives one that keeps its values in memory.
/// A value that is missing or broken gives the value of the first start. The store never fails.
/// The settings of the shell (the hotkeys) are in `SettingsStore`. The two share no key.
/// The settings window writes the two seconds values here (D12), and the session reads them.
struct DrawPrefs {
    private enum Key {
        static let tool = "drawTool"
        static let size = "drawSize"
        static let color = "drawColor"
        static let stay = "drawStayMode"
        static let fadeSeconds = "drawFadeSeconds"
        static let holdSeconds = "drawHoldSeconds"
    }

    /// Fade seconds and Hold seconds are whole numbers in this range (row 3.21).
    static let secondsRange = 1...60
    /// The start values (row 3.20).
    static let firstFadeSeconds = 2
    static let firstHoldSeconds = 5

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

    /// A Fade mark is gone this many seconds after it is finished.
    var fadeSeconds: Int {
        get { seconds(Key.fadeSeconds) ?? DrawPrefs.firstFadeSeconds }
        nonmutating set { defaults.set(newValue, forKey: Key.fadeSeconds) }
    }

    /// The Hold marks stay at full strength this many seconds after the last drawing activity.
    var holdSeconds: Int {
        get { seconds(Key.holdSeconds) ?? DrawPrefs.firstHoldSeconds }
        nonmutating set { defaults.set(newValue, forKey: Key.holdSeconds) }
    }

    /// A stored value that is not valid gives the start value (row 3.26).
    private func seconds(_ key: String) -> Int? {
        (defaults.object(forKey: key) as? Int).flatMap { DrawPrefs.secondsRange.contains($0) ? $0 : nil }
    }

    private func read<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        (defaults.object(forKey: key) as? String).flatMap(Value.init(rawValue:))
    }
}
