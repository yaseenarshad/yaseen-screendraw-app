// Draws the app icon and writes `Support/AppIcon.icns`.
//
// USAGE (from the repository root):
//   swift scripts/make-icon.swift
//
// The script draws each size of the icon into `build/AppIcon.iconset`, then
// `iconutil` packs the sizes into `Support/AppIcon.icns`. It also writes three
// preview pictures: `build/icon-preview-512.png`, `build/icon-preview-32.png`
// and `build/icon-preview-16.png`. It uses only AppKit and tools that come with
// Xcode. Run it again after a change to the drawing.

import AppKit

/// The hand-written "Y": one pen stroke, in a 56 x 56 box, with y down (as in SVG).
/// Each row is one cubic curve: control point 1, control point 2, end point.
/// The stroke starts at the top of the left arm, goes down into the bowl, up
/// the right arm, then down the tail and into the hook.
let strokeStart = CGPoint(x: 15, y: 15)
let strokeCurves: [(c1: CGPoint, c2: CGPoint, end: CGPoint)] = [
    (CGPoint(x: 16, y: 24), CGPoint(x: 21, y: 31), CGPoint(x: 27, y: 29)),
    (CGPoint(x: 33, y: 27), CGPoint(x: 37, y: 19), CGPoint(x: 40, y: 13)),
    (CGPoint(x: 40, y: 23), CGPoint(x: 38, y: 33), CGPoint(x: 33, y: 41)),
    (CGPoint(x: 29, y: 47), CGPoint(x: 22, y: 47), CGPoint(x: 19, y: 42)),
]
/// The width of the pen in the 56 x 56 box, for the large sizes.
let strokeWidth: CGFloat = 4.6

/// The small sizes get a larger letter and a thicker pen. Without this the pen
/// is 1 pixel wide at 16 pixels, and the "Y" is a grey blur.
/// - `scale`: the size of the letter, where 1 is the size of the mockup.
/// - `width`: the width of the pen in the 56 x 56 box, before `scale`.
func glyphTuning(pixels: Int) -> (scale: CGFloat, width: CGFloat) {
    switch pixels {
    case ...16: return (1.22, 6.4)
    case ...32: return (1.12, 5.4)
    case ...64: return (1.05, 5.0)
    default: return (1.0, strokeWidth)
    }
}

/// Draws the icon into a square of `pixels` x `pixels`.
func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // All the numbers below are for a 1024 canvas. `u` scales them.
    let u = CGFloat(pixels) / 1024.0

    // The background: a rounded square on the icon grid of macOS (824 of 1024),
    // in the indigo of the Yaseen Docs, Yaseen Draw and Yaseen Screenshot icons.
    let body = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    NSColor(srgbRed: 0.42, green: 0.40, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u).fill()

    // The glyph: the 56 x 56 box of the stroke fills the indigo square.
    // AppKit has y up, so the y of each point is turned over.
    let tuning = glyphTuning(pixels: pixels)
    let s = body.width / 56.0 * tuning.scale
    let letter = NSBezierPath()
    letter.lineWidth = tuning.width * s
    letter.lineCapStyle = .round
    letter.lineJoinStyle = .round
    func point(_ p: CGPoint) -> NSPoint {
        NSPoint(x: p.x * s, y: -p.y * s)
    }
    letter.move(to: point(strokeStart))
    for curve in strokeCurves {
        letter.curve(to: point(curve.end), controlPoint1: point(curve.c1), controlPoint2: point(curve.c2))
    }
    // Put the middle of the letter on the middle of the square.
    let bounds = letter.bounds
    let move = AffineTransform(translationByX: body.midX - bounds.midX, byY: body.midY - bounds.midY)
    letter.transform(using: move)
    NSColor.white.setStroke()
    letter.stroke()

    return rep
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("cannot make the PNG data for \(url.lastPathComponent)")
    }
    do {
        try png.write(to: url)
    } catch {
        fail("cannot write \(url.lastPathComponent): \(error)")
    }
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
guard fileManager.fileExists(atPath: root.appendingPathComponent("Support/Info.plist").path) else {
    fail("run this script from the repository root: swift scripts/make-icon.swift")
}

let buildDir = root.appendingPathComponent("build")
let iconset = buildDir.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Support/AppIcon.icns")

try? fileManager.removeItem(at: iconset)
do {
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("cannot make \(iconset.path): \(error)")
}

// The file names and pixel sizes that `iconutil` expects.
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    writePNG(drawIcon(pixels: entry.pixels), to: iconset.appendingPathComponent(entry.name))
}

// The previews are the same drawings as the sizes in the .icns file.
for pixels in [512, 32, 16] {
    writePNG(drawIcon(pixels: pixels), to: buildDir.appendingPathComponent("icon-preview-\(pixels).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
do {
    try iconutil.run()
} catch {
    fail("cannot start iconutil: \(error)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil failed with status \(iconutil.terminationStatus)")
}

try? fileManager.removeItem(at: iconset)
print("Wrote \(output.path)")
print("Wrote the previews: build/icon-preview-512.png, build/icon-preview-32.png, build/icon-preview-16.png")
