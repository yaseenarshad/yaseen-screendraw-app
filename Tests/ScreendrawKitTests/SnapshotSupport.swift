import AppKit
import Testing

/// A picture of a view, made with no window. Nothing goes to a screen.
@MainActor
struct Snapshot {
    let bitmap: NSBitmapImageRep
    /// The size in pixels.
    let width: Int
    let height: Int

    /// Draws the view and its subviews into a bitmap at `scale`.
    init(of view: NSView, scale: CGFloat = 2) throws {
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        width = Int(size.width * scale)
        height = Int(size.height * scale)
        bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        // The bitmap has the size of the view in points, so AppKit draws at `scale`.
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    /// One pixel. The top-left of the picture is 0, 0.
    subscript(x: Int, y: Int) -> Pixel {
        guard let data = bitmap.bitmapData else { return .clear }
        let offset = y * bitmap.bytesPerRow + x * 4
        return Pixel(red: data[offset], green: data[offset + 1], blue: data[offset + 2], alpha: data[offset + 3])
    }

    /// Writes the picture as a PNG into the folder that `SCREENDRAW_PNG_DIR` names.
    /// Without that value, a test run writes no file.
    func write(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["SCREENDRAW_PNG_DIR"], !folder.isEmpty else { return }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
}
