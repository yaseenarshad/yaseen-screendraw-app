import AppKit
@testable import ScreendrawKit
import Testing

/// A picture of some views on a backdrop, at the places that they have on the screen. The tests
/// draw it with no window. Nothing goes to a screen.
@MainActor
struct Scene {
    /// The part of the screen that the picture shows, in the global points of AppKit.
    let area: CGRect
    private var parts: [(view: NSView, frame: CGRect, strength: CGFloat)] = []

    init(area: CGRect) {
        self.area = area
    }

    /// Adds a view at its frame on the screen. `strength` is the `alphaValue` of its window.
    mutating func add(_ view: NSView, frame: CGRect, strength: CGFloat = 1) {
        parts.append((view, frame, strength))
    }

    /// Draws the scene, and writes it as a PNG into the folder that `SCREENDRAW_PNG_DIR` names.
    /// Without that value, a test run writes no file.
    @discardableResult
    func write(_ name: String, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(area.width * scale), pixelsHigh: Int(area.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = area.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // A made-up desktop: a light page with some lines of text, so a dim toolbar shows what is below it.
        NSColor(white: 0.93, alpha: 1).setFill()
        CGRect(origin: .zero, size: area.size).fill()
        NSColor(white: 0.55, alpha: 1).setFill()
        for line in stride(from: CGFloat(10), to: area.height, by: 14) {
            CGRect(x: 10, y: line, width: area.width - 20 - CGFloat(Int(line) % 5) * 30, height: 4).fill()
        }
        for part in parts {
            let picture = try Snapshot(of: part.view, scale: scale).bitmap
            picture.draw(
                in: part.frame.offsetBy(dx: -area.minX, dy: -area.minY), from: .zero,
                operation: .sourceOver, fraction: part.strength, respectFlipped: false, hints: nil
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        if let folder = ProcessInfo.processInfo.environment["SCREENDRAW_PNG_DIR"], !folder.isEmpty {
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        }
        return bitmap
    }
}

/// The pictures of the toolbar for the review (YAZ-2830, YAZ-2827): each form, with the tools of
/// the app and with nine tools, the tip, and the dim toolbar of click-through.
/// `SCREENDRAW_PNG_DIR="$PWD/build" swift test` writes them. A usual test run writes no file.
@MainActor @Suite struct ToolbarPictureTests {
    @Test func eachFormWithTheToolsOfTheAppAndWithNineTools() throws {
        let fixture = Fixture()
        for (tools, suffix) in [(Tool.allCases, ""), (ToolbarFormTests.nineTools, "-9")] {
            let toolbar = Toolbar(session: fixture.session, tools: tools)
            for (form, name) in [(ToolbarForm.row, "row"), (.twoRows, "two-rows"), (.column, "column"), (.twoColumns, "two-columns")] {
                toolbar.form = form
                #expect(toolbar.frame.size == toolbar.layout.size)
                let picture = try Snapshot(of: toolbar, scale: 2)
                // The picture is not empty: the middle of the grip area has the colour of the toolbar or of a dot.
                #expect(picture[Int(toolbar.layout.grip.midX * 2), Int(toolbar.layout.grip.midY * 2)].alpha > 200)
                try picture.write("v020-bar-\(name)\(suffix).png")
            }
        }
    }

    /// The toolbar and the tip of a button, at the places that the controller gives them.
    @Test func theTipAtAColumnAndAtARow() throws {
        let stage = DrawControllerTests.Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()

        /// The toolbar with the tip of one button, and some of the screen around the two.
        func picture(_ button: String, _ name: String) throws {
            try stage.toolbar.pointerMoved(to: nil)
            try stage.rest(on: button)
            let panel = try stage.panel, tip = try #require(stage.controller.tipPanel)
            let tipView = try #require(tip.contentView)
            #expect(!panel.frame.intersects(tip.frame) && Desks.main.visibleFrame.contains(tip.frame))
            // The tip is not empty, and its text fits in it.
            let text = try #require(tipView as? ToolbarTipView).text
            #expect(tipView.bounds.insetBy(dx: 6, dy: 3).size.width >= text.size().width)
            var scene = Scene(area: panel.frame.union(tip.frame).insetBy(dx: -20, dy: -20))
            scene.add(panel.toolbarView, frame: panel.frame, strength: panel.alphaValue)
            scene.add(tipView, frame: tip.frame)
            try scene.write(name)
        }

        // The row at the bottom centre: the tip is above the button.
        try picture("Arrow", "v020-bar-row-tip.png")
        // The column at the left edge: the tip is at its right.
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 1000))
        #expect(try stage.toolbar.form == .column)
        try picture("Arrow", "v020-bar-tip.png")
        try picture("Settings", "v020-bar-tip-gear.png")
        // The column at the right edge: the tip is at its left.
        try stage.drag(from: stage.grip, to: CGPoint(x: 1900, y: 1000))
        try picture("Sticky", "v020-bar-tip-right.png")
    }

    /// Version 0.3.0 (YAZ-2837): the toolbar with the "Click through" button, as a row and as a
    /// column, in mode drawing and in click-through with the lit button, and the tip of that button.
    @Test func theToolbarWithTheClickThroughButtonInDrawingAndInClickThrough() throws {
        let stage = DrawControllerTests.Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()

        /// The toolbar as it is on the screen now, with the tip of one button if `tipOf` names one.
        @discardableResult
        func picture(_ name: String, tipOf button: String? = nil) throws -> NSBitmapImageRep {
            let panel = try stage.panel
            try stage.toolbar.pointerMoved(to: nil)
            var area = panel.frame
            var tip: ToolbarTip?
            if let button = button {
                try stage.rest(on: button)
                let shown = try #require(stage.controller.tipPanel)
                #expect(!panel.frame.intersects(shown.frame) && Desks.main.visibleFrame.contains(shown.frame))
                area = area.union(shown.frame)
                tip = shown
            }
            var scene = Scene(area: area.insetBy(dx: -20, dy: -20))
            scene.add(panel.toolbarView, frame: panel.frame, strength: panel.alphaValue)
            if let tip = tip { scene.add(try #require(tip.contentView), frame: tip.frame) }
            return try scene.write(name)
        }

        /// How light the background of a button is in a picture of the toolbar alone: 0 is black, 1 is white.
        /// The point is 3 points inside the top-left corner of the button, where no picture and no key is.
        func background(of name: String, in bitmap: NSBitmapImageRep) throws -> CGFloat {
            let frame = try stage.toolbar.button(named: name).frame
            let color = try #require(bitmap.colorAt(x: Int((20 + frame.minX + 3) * 2), y: Int((20 + frame.minY + 3) * 2)))
            return color.redComponent
        }

        // Mode drawing: the row at the bottom centre. "Click through" is not lit, and the Pen is.
        let row = try picture("v030-bar-row.png")
        #expect(try background(of: "Pen", in: row) > background(of: "Click through", in: row) + 0.1)
        try picture("v030-bar-row-tip.png", tipOf: "Click through")
        #expect(stage.tip == "Click through  esc")

        // Click-through: the toolbar is dim, and "Click through" is lit. On the dim toolbar the lit
        // button is still clearly lighter than a button that is not lit.
        try stage.press("Click through")
        #expect(try stage.panel.alphaValue == 0.5)
        let dimRow = try picture("v030-bar-row-clickthrough.png")
        #expect(try background(of: "Click through", in: dimRow) > background(of: "Arrow", in: dimRow) + 0.05)
        try picture("v030-bar-row-clickthrough-tip.png", tipOf: "Click through")

        // The column at the left edge, in click-through and in mode drawing.
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 1000))
        #expect(try stage.toolbar.form == .column && stage.controller.mode == .clickThrough)
        let dimColumn = try picture("v030-bar-column-clickthrough.png")
        #expect(try background(of: "Click through", in: dimColumn) > background(of: "Arrow", in: dimColumn) + 0.05)
        try picture("v030-bar-column-tip.png", tipOf: "Click through")
        try stage.press("Click through")
        #expect(stage.controller.mode == .drawing)
        let column = try picture("v030-bar-column.png")
        #expect(try background(of: "Pen", in: column) > background(of: "Click through", in: column) + 0.1)
        try picture("v030-bar-column-close-tip.png", tipOf: "Close")
        #expect(stage.tip == "Close")
    }

    /// Click-through: the toolbar is at half strength, and the screen shows through it (row 4.2).
    @Test func theDimToolbarOfClickThrough() throws {
        let stage = DrawControllerTests.Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        stage.session.drawLine(on: Desks.main.display.id)
        try stage.toolbar.press("Settings")
        #expect(stage.controller.mode == .clickThrough)

        for name in ["v020-bar-dim.png", "v020-bar-dim-column.png"] {
            let panel = try stage.panel
            #expect(panel.alphaValue == 0.5)
            var scene = Scene(area: panel.frame.insetBy(dx: -20, dy: -20))
            scene.add(panel.toolbarView, frame: panel.frame, strength: panel.alphaValue)
            let bitmap = try scene.write(name)
            // The toolbar is see-through: its dark background is lighter than at full strength.
            let middle = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 40 + 6))
            #expect(middle.redComponent > 0.3)
            // The drag of the toolbar works in click-through too.
            try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 1000))
        }
        #expect(stage.controller.mode == .clickThrough)
    }
}
