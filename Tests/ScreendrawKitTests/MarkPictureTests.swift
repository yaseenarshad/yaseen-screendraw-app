import AppKit
@testable import ScreendrawKit
import Testing

/// The pictures of the new marks for the review (YAZ-2828 and YAZ-2829): a line, the stamps in
/// each colour and size, a selected rectangle with its handles and a selected text, on a light
/// and on a dark background. The tests draw layers into a bitmap. Nothing goes to a screen.
/// `SCREENDRAW_PNG_DIR` names the folder for the files. Without it, a test run writes no file.
@MainActor @Suite struct MarkPictureTests {
    /// A bitmap that a test fills with layers, each on its own background.
    @MainActor final class Picture {
        let size: CGSize
        let scale: CGFloat
        private let context: CGContext

        init(size: CGSize, scale: CGFloat) throws {
            self.size = size
            self.scale = scale
            context = try #require(CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.scaleBy(x: scale, y: scale)
        }

        /// Draws a layer of `area` points on a background. `origin` is the top-left of the area in the picture.
        func draw(_ layer: CALayer, area: CGSize, at origin: CGPoint, background: CGColor) {
            context.saveGState()
            context.translateBy(x: origin.x, y: size.height - origin.y - area.height)
            context.setFillColor(background)
            context.fill(CGRect(origin: .zero, size: area))
            layer.render(in: context)
            context.restoreGState()
        }

        /// One pixel at a place in points. The top-left of the picture is 0, 0.
        func pixel(_ x: CGFloat, _ y: CGFloat) throws -> Pixel {
            let image = try #require(context.makeImage())
            let data = try #require(image.dataProvider?.data as Data?)
            let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
            return Pixel(red: data[offset], green: data[offset + 1], blue: data[offset + 2], alpha: data[offset + 3])
        }

        func write(_ name: String) throws {
            guard let folder = ProcessInfo.processInfo.environment["SCREENDRAW_PNG_DIR"], !folder.isEmpty else { return }
            let image = try #require(context.makeImage())
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        }
    }

    private static let light = CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    private static let dark = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let stampArea = CGSize(width: 420, height: 300)
    private static let overlayArea = CGSize(width: 400, height: 300)

    /// The stamps 1 to 3 in each colour and each size, and three numbers with more digits.
    /// The marks are in a layer that has y going down, as the layer of the marks in the overlay.
    private func stampsLayer(scale: CGFloat) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: MarkPictureTests.stampArea)
        let layer = CALayer()
        layer.frame = root.bounds
        layer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
        root.addSublayer(layer)
        for (row, color) in MarkColor.allCases.enumerated() {
            let y = CGFloat(38 + row * 44)
            var x: CGFloat = 12
            for size in MarkSize.allCases {
                let style = MarkStyle(color: color, size: size)
                for number in 1...3 {
                    let middle = CGPoint(x: x + style.stampDiameter / 2, y: y)
                    layer.addSublayer(MarkRenderer.makeLayer(for: Mark(tool: .stamp, style: style, points: [middle], number: number), scale: scale))
                    x += style.stampDiameter + 6
                }
                x += 8
            }
            let more = [10, 27, 128, 9, 45, 300][row]
            let style = MarkStyle(color: color, size: [.thick, .medium, .thin][row % 3])
            layer.addSublayer(MarkRenderer.makeLayer(
                for: Mark(tool: .stamp, style: style, points: [CGPoint(x: 380, y: y)], number: more), scale: scale
            ))
        }
        return root
    }

    /// One overlay with a line, an arrow, a pen line, three stamps, a rectangle and a text.
    /// `selectAt` is the place of the click with Select.
    private func overlay(scale: CGFloat, selectAt place: CGPoint) throws -> OverlayViewTests.Stage {
        let stage = OverlayViewTests.Stage(scale: scale)
        let session = stage.session
        session.selectTool(.line)
        try stage.drag(from: point(30, 40), to: point(170, 70))
        session.setColor(.blue)
        session.selectTool(.arrow)
        try stage.drag(from: point(220, 70), to: point(360, 40))
        session.setColor(.green)
        session.selectTool(.stamp)
        for x in [40, 90, 140] as [CGFloat] { try stage.click(at: point(x, 250)) }
        session.setColor(.red)
        session.selectTool(.rectangle)
        try stage.drag(from: point(60, 110), to: point(200, 200))
        session.setColor(.amber)
        session.selectTool(.text)
        try stage.click(at: point(240, 150))
        session.textChanged("Step 2: here")
        session.completeText()
        session.selectTool(.select)
        try stage.click(at: place)
        #expect(session.selectedID != nil)
        return stage
    }

    @Test func thePicturesOfTheNewMarksOnALightAndOnADarkBackground() throws {
        let stamps = MarkPictureTests.stampArea, overlay = MarkPictureTests.overlayArea
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
        let blue = Pixel(red: 26, green: 140, blue: 255, alpha: 255)
        for scale in [2, 1] as [CGFloat] {
            let picture = try Picture(size: CGSize(width: stamps.width + 2 * overlay.width, height: 2 * overlay.height), scale: scale)
            let onlyStamps = try Picture(size: CGSize(width: 2 * stamps.width, height: stamps.height), scale: scale)
            for (row, background) in [MarkPictureTests.light, MarkPictureTests.dark].enumerated() {
                let top = CGFloat(row) * overlay.height
                picture.draw(stampsLayer(scale: scale), area: stamps, at: point(0, top), background: background)
                onlyStamps.draw(stampsLayer(scale: scale), area: stamps, at: point(CGFloat(row) * stamps.width, 0), background: background)
                // The selected rectangle with its eight handles, and the selected text.
                let rectangle = try self.overlay(scale: scale, selectAt: point(60, 150))
                picture.draw(rectangle.view.canvasLayer, area: overlay, at: point(stamps.width, top), background: background)
                let text = try self.overlay(scale: scale, selectAt: point(260, 150))
                #expect(text.session.selectedMark(on: text.display.id)?.tool == .text)
                picture.draw(text.view.canvasLayer, area: overlay, at: point(stamps.width + overlay.width, top), background: background)

                // The handles show on the two backgrounds: each one is white, with a blue edge.
                for (x, y) in [(60, 110), (130, 110), (200, 110), (200, 155), (200, 200), (130, 200), (60, 200), (60, 155)] as [(CGFloat, CGFloat)] {
                    #expect(try picture.pixel(stamps.width + x, top + y) == white, "the handle at \(x), \(y)")
                    #expect(try picture.pixel(stamps.width + x - 3.5, top + y).isNear(blue), "the edge of the handle at \(x), \(y)")
                }
                // The outline of the selected text: its top line has white and blue pixels on the two backgrounds.
                let outline = try #require(text.session.selectedMark(on: text.display.id)).outline.integral
                var whitePixels = 0, bluePixels = 0
                for step in 0..<Int(outline.width - 2) {
                    let pixel = try picture.pixel(stamps.width + overlay.width + outline.minX + 1 + CGFloat(step), top + outline.minY)
                    if pixel == white { whitePixels += 1 } else if pixel.isNear(blue) { bluePixels += 1 }
                }
                #expect(whitePixels > 20 && bluePixels > 20 && whitePixels + bluePixels == Int(outline.width - 2))
            }
            try picture.write(scale == 2 ? "v020-marks.png" : "v020-marks-1x.png")
            try onlyStamps.write(scale == 2 ? "v020-stamps.png" : "v020-stamps-1x.png")
        }
    }
}
