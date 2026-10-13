import AppKit
@testable import ScreendrawKit
import Testing

// Shared helpers. Everything here stays out of sight: no window on a screen, no real screen,
// no mouse, no key, and no file on the disk.

/// The clock of a test. The test sets the time. No test sleeps.
final class TestClock {
    var time: TimeInterval = 1000
}

/// A `UserDefaults` that keeps its values in memory only, for one test. All the tests use it.
///
/// A real suite (`UserDefaults(suiteName:)`) is not possible here: macOS writes a file for it in
/// `~/Library/Preferences`, and writes an empty file again some seconds after `removePersistentDomain`.
/// The tests must leave no file.
final class MemoryDefaults: UserDefaults {
    /// Everything that the app saved.
    private(set) var values: [String: Any] = [:]

    init() {
        // The name is never used: each call that the app makes is overridden below.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { change(defaultName, value) }
    override func set(_ value: Int, forKey defaultName: String) { change(defaultName, value) }
    override func set(_ value: Double, forKey defaultName: String) { change(defaultName, value) }
    override func set(_ value: Bool, forKey defaultName: String) { change(defaultName, value) }
    override func removeObject(forKey defaultName: String) { change(defaultName, nil) }

    /// The real `UserDefaults` posts this notification on the thread that writes, before the write returns.
    private func change(_ key: String, _ value: Any?) {
        values[key] = value
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
    }
}

/// Two screens, the same mix as the two real monitors: the left has scale 2, the right has scale 1.
enum Screens {
    static let left = DrawDisplay(id: 1, size: CGSize(width: 800, height: 600))
    static let right = DrawDisplay(id: 2, size: CGSize(width: 400, height: 300))

    /// The left screen has a menu bar of 25 points and a Dock of 50 points.
    static let leftScreen = OverlayScreen(
        display: left,
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        visibleFrame: CGRect(x: 0, y: 50, width: 800, height: 525),
        scale: 2
    )
    static let rightScreen = OverlayScreen(
        display: right,
        frame: CGRect(x: 800, y: 0, width: 400, height: 300),
        visibleFrame: CGRect(x: 800, y: 0, width: 400, height: 275),
        scale: 1
    )
}

/// A session with a clock that the test sets and settings that the test owns.
/// Drawing is on for the two screens, unless `isOn` is false.
struct Fixture {
    let clock = TestClock()
    let store = MemoryDefaults()
    let session: DrawSession

    init(isOn: Bool = true) {
        session = Fixture.makeSession(clock: clock, store: store)
        if isOn { session.start(displays: [Screens.left, Screens.right]) }
    }

    /// A second session that reads the same settings: the next start of the app.
    func nextStart() -> DrawSession {
        Fixture.makeSession(clock: clock, store: store)
    }

    private static func makeSession(clock: TestClock, store: MemoryDefaults) -> DrawSession {
        DrawSession(prefs: DrawPrefs(defaults: store), now: { clock.time })
    }
}

extension Toolbar {
    /// The button with the given name ("Pen", "Undo", "Thick", "Blue", "Sticky" and so on).
    func button(named name: String) throws -> ToolbarButton {
        try #require(subviews.compactMap { $0 as? ToolbarButton }.first { $0.name == name })
    }

    /// A click on a button: its action, as AppKit sends it. Nothing clicks.
    func press(_ name: String) throws {
        let button = try button(named: name)
        #expect(button.isEnabled, "the button \(name) is not enabled")
        // The action goes through the app object. It is an accessory app: no Dock icon, no window.
        NSApplication.shared.setActivationPolicy(.accessory)
        #expect(button.sendAction(button.action, to: button.target))
    }
}

extension DrawSession {
    /// A pointer down, the moves through `points`, and a pointer up at the last point.
    func drag(_ points: [CGPoint], on displayID: CGDirectDisplayID = Screens.left.id) {
        pointerDown(at: points[0], on: displayID)
        for point in points.dropFirst() {
            pointerDragged(to: point)
        }
        pointerUp(at: points[points.count - 1])
    }

    /// A click with no move.
    func click(at point: CGPoint, on displayID: CGDirectDisplayID = Screens.left.id) {
        drag([point], on: displayID)
    }

    /// One Pen line on the left screen. `row` moves it down, so each line is different.
    func drawLine(row: Int = 0, on displayID: CGDirectDisplayID = Screens.left.id) {
        let y = CGFloat(20 + 10 * row)
        drag([CGPoint(x: 20, y: y), CGPoint(x: 120, y: y)], on: displayID)
    }

    /// The marks of the two test screens, the left screen first.
    var allMarks: [PlacedMark] {
        marks(on: Screens.left.id) + marks(on: Screens.right.id)
    }
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

/// One pixel with its alpha. The colour parts are multiplied by the alpha, as the bitmap holds them.
struct Pixel: Equatable, CustomStringConvertible {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    static let clear = Pixel(red: 0, green: 0, blue: 0, alpha: 0)

    var description: String { "(\(red), \(green), \(blue), \(alpha))" }

    /// A mark colour at the given strength, as a pixel.
    init(_ color: MarkColor, alpha: CGFloat = 1) {
        let parts = color.components
        self.init(
            red: UInt8((parts.red * alpha * 255).rounded()),
            green: UInt8((parts.green * alpha * 255).rounded()),
            blue: UInt8((parts.blue * alpha * 255).rounded()),
            alpha: UInt8((alpha * 255).rounded())
        )
    }

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// True when each part differs by `tolerance` at most. A drawn edge is not exact to the last bit.
    func isNear(_ other: Pixel, tolerance: Int = 4) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
            && abs(Int(alpha) - Int(other.alpha)) <= tolerance
    }
}

/// Reads one pixel of a bitmap (top-left origin).
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Draws a layer into a bitmap of `size` points at `scale`. Nothing goes to a screen.
    init(layer: CALayer, size: CGSize, scale: CGFloat) {
        let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
        width = pixelWidth
        height = pixelHeight
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        buffer.withUnsafeMutableBytes { pointer in
            let context = CGContext(
                data: pointer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
        }
        bytes = buffer
    }

    subscript(x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
    }

    /// The number of pixels in the area that are not transparent.
    func inkCount(x: Range<Int>, y: Range<Int>) -> Int {
        var count = 0
        for row in y {
            for column in x where self[column, row].alpha > 0 {
                count += 1
            }
        }
        return count
    }
}
