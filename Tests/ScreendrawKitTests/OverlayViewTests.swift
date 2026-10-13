import AppKit
@testable import ScreendrawKit
import Testing

/// The view adapter, out of sight. The test hands `NSEvent` objects to the view (it posts no
/// event to macOS) and draws the layers of the view into a bitmap. No window is shown.
@MainActor @Suite struct OverlayViewTests {
    /// One overlay view on a fake screen of 400 by 300 points, wired as `DrawController` wires it.
    @MainActor final class Stage {
        let clock = TestClock()
        let store = TestDefaults()
        let display = DrawDisplay(id: 7, size: CGSize(width: 400, height: 300))
        let scale: CGFloat
        let session: DrawSession
        let view: OverlayView

        init(scale: CGFloat = 2) {
            self.scale = scale
            session = DrawSession(prefs: DrawPrefs(defaults: store.defaults), now: { [clock] in clock.time })
            session.start(displays: [display])
            view = OverlayView(display: display, scale: scale, session: session)
            session.onChange = { [unowned self] in self.view.refresh() }
        }

        /// A mouse event at a point with a top-left origin. AppKit itself counts from the bottom.
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ yFromTop: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: x, y: view.bounds.height - yFromTop),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        func key(_ keyCode: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
        }

        func drag(from start: CGPoint, to end: CGPoint) throws {
            view.mouseDown(with: try mouse(.leftMouseDown, start.x, start.y))
            view.mouseDragged(with: try mouse(.leftMouseDragged, end.x, end.y))
            view.mouseUp(with: try mouse(.leftMouseUp, end.x, end.y))
        }

        func click(at point: CGPoint) throws {
            view.mouseDown(with: try mouse(.leftMouseDown, point.x, point.y))
            view.mouseUp(with: try mouse(.leftMouseUp, point.x, point.y))
        }

        /// What the overlay shows, in the pixels of the screen (top-left origin).
        func pixels() -> PixelReader {
            PixelReader(layer: view.canvasLayer, size: display.size, scale: scale)
        }

        /// The pixel at a place in points (top-left origin).
        func pixel(_ x: CGFloat, _ y: CGFloat, in pixels: PixelReader) -> Pixel {
            pixels[Int(x * scale), Int(y * scale)]
        }
    }

    // MARK: The pen

    @Test func row1_4_aMouseDragDrawsALineOnATransparentOverlay() throws {
        let stage = Stage()
        let view = stage.view
        // Before a drag, the overlay shows nothing: each pixel is transparent.
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)

        view.mouseDown(with: try stage.mouse(.leftMouseDown, 50, 100))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 150, 100))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 250, 100))
        // The line follows the pointer during the drag: it is 100 points from the top, not from the bottom.
        var pixels = stage.pixels()
        #expect(stage.pixel(150, 100, in: pixels) == Pixel(.red))
        #expect(stage.pixel(150, 200, in: pixels) == .clear)
        #expect(view.draftLayer.path != nil && view.markLayers.isEmpty)

        view.mouseUp(with: try stage.mouse(.leftMouseUp, 250, 100))
        #expect(stage.session.marks(on: stage.display.id).map { $0.mark.points } == [[point(50, 100), point(150, 100), point(250, 100)]])
        // The finished mark has its own layer, and the layer of the drag is empty again.
        #expect(view.markLayers.count == 1 && view.draftLayer.path == nil)

        // The Thick pen is 7 points wide, with round ends.
        pixels = stage.pixels()
        for x in [50, 150, 250] as [CGFloat] {
            #expect(stage.pixel(x, 100, in: pixels) == Pixel(.red))
            #expect(stage.pixel(x, 97.5, in: pixels) == Pixel(.red))
            #expect(stage.pixel(x, 102.5, in: pixels) == Pixel(.red))
            #expect(stage.pixel(x, 95, in: pixels) == .clear)
            #expect(stage.pixel(x, 105, in: pixels) == .clear)
        }
        #expect(stage.pixel(48, 100, in: pixels) == Pixel(.red))
        #expect(stage.pixel(44, 100, in: pixels) == .clear)
        #expect(stage.pixel(256, 100, in: pixels) == .clear)
    }

    @Test func row1_4_theLineIsAtTheSamePlaceOnAScreenOfScale1() throws {
        let stage = Stage(scale: 1)
        try stage.drag(from: point(50, 100), to: point(250, 100))
        let pixels = stage.pixels()
        #expect(pixels.width == 400 && pixels.height == 300)
        #expect(pixels[150, 100] == Pixel(.red))
        #expect(pixels[150, 94] == .clear && pixels[150, 106] == .clear && pixels[150, 200] == .clear)
    }

    @Test func row1_5_aClickWithThePenMakesOneRoundDot() throws {
        let stage = Stage()
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, 100, 100))
        // The dot shows at the pointer down.
        #expect(stage.pixel(100, 100, in: stage.pixels()) == Pixel(.red))
        stage.view.mouseUp(with: try stage.mouse(.leftMouseUp, 100, 100))

        let pixels = stage.pixels()
        #expect(stage.session.markCount == 1)
        // A dot of 7 points: red in the middle and 2.5 points to each side, clear at its corners.
        for (dx, dy) in [(0, 0), (2.5, 0), (-2.5, 0), (0, 2.5), (0, -2.5)] as [(CGFloat, CGFloat)] {
            #expect(stage.pixel(100 + dx, 100 + dy, in: pixels) == Pixel(.red))
        }
        for (dx, dy) in [(3, 3), (-3.5, 3), (5, 0), (-5, 0), (0, 5), (0, -5)] as [(CGFloat, CGFloat)] {
            #expect(stage.pixel(100 + dx, 100 + dy, in: pixels) == .clear)
        }
        #expect(pixels.inkCount(x: 0..<800, y: 0..<600) < 200)
    }

    @Test func row1_12_aNewPointChangesOnlyTheLayerOfTheLineInProgress() throws {
        let stage = Stage()
        let view = stage.view
        try stage.drag(from: point(20, 20), to: point(120, 20))
        try stage.drag(from: point(20, 40), to: point(120, 40))
        stage.session.selectTool(.text)
        try stage.click(at: point(200, 200))
        stage.session.textChanged("Note")
        stage.session.completeText()
        stage.session.selectTool(.pen)

        // Three finished marks: three layers with their pictures.
        let ids = stage.session.marks(on: stage.display.id).map { $0.id }
        let layers = try ids.map { try #require(view.markLayers[$0]) }
        let paths = layers.map { ($0 as? CAShapeLayer)?.path }
        let text = try #require(layers[2].contents as AnyObject?)
        #expect(paths[0] != nil && paths[1] != nil && paths[2] == nil)

        view.mouseDown(with: try stage.mouse(.leftMouseDown, 10, 150))
        var lastWidth: CGFloat = 0
        for step in 1...300 {
            view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 10 + CGFloat(step), 150 + CGFloat(step % 7)))
            // Only the path of the line in progress grows.
            let width = try #require(view.draftLayer.path).boundingBoxOfPath.width
            #expect(width > lastWidth)
            lastWidth = width
        }
        // The finished marks have the same layers with the same paths and the same image: nothing made them again.
        for (index, id) in ids.enumerated() {
            #expect(view.markLayers[id] === layers[index])
            #expect(((layers[index] as? CAShapeLayer)?.path as AnyObject?) === (paths[index] as AnyObject?))
        }
        #expect((layers[2].contents as AnyObject?) === text)
        #expect(view.markLayers.count == 3)

        // The pointer up makes one new layer. The three old layers stay.
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 310, 150))
        #expect(view.markLayers.count == 4 && view.draftLayer.path == nil)
        for (index, id) in ids.enumerated() {
            #expect(view.markLayers[id] === layers[index])
        }
    }

    @Test func row1_12_theLineInProgressHasTheSamePathAsTheFinishedMark() throws {
        let stage = Stage()
        let view = stage.view
        for tool in [Tool.pen, .highlight] {
            stage.session.selectTool(tool)
            // The first drag is a click, and each drag starts at a different place: the curves
            // of one line must not show in the next line.
            try stage.click(at: point(300, 20))
            for start in [point(20, 50), point(200, 250)] {
                view.mouseDown(with: try stage.mouse(.leftMouseDown, start.x, start.y))
                for step in 1...40 {
                    let x = start.x + CGFloat(step) * 3, y = start.y + CGFloat((step * 7) % 23)
                    view.mouseDragged(with: try stage.mouse(.leftMouseDragged, x, y))
                    // The path that grew by one curve is the path that the finished mark gets.
                    let draft = try #require(stage.session.draft(on: stage.display.id))
                    #expect(draft.points.count == step + 1)
                    #expect(view.draftLayer.path == MarkRenderer.path(for: draft))
                }
                view.mouseUp(with: try stage.mouse(.leftMouseUp, start.x + 120, start.y))
            }
        }
        // Each finished layer has the path of its mark.
        for placed in stage.session.marks(on: stage.display.id) {
            let layer = try #require(view.markLayers[placed.id] as? CAShapeLayer)
            #expect(layer.path == MarkRenderer.path(for: placed.mark))
        }
        // The Pen click is a dot. The Highlight click made no mark.
        #expect(stage.session.markCount == 5)
    }

    @Test func theLayersHaveNoImplicitAnimation() throws {
        let stage = Stage()
        try stage.drag(from: point(20, 20), to: point(120, 20))
        let finished = try #require(stage.view.markLayers.values.first)
        for layer in [stage.view.draftLayer, finished] {
            for key in ["path", "opacity", "hidden", "strokeColor", "lineWidth", "contents", "position", "bounds"] {
                #expect(layer.action(forKey: key) == nil, "the layer animates \(key)")
            }
        }
    }

    // MARK: The other tools

    @Test func row2_5_highlightIsAWideLineThatIsSeeThrough() throws {
        let stage = Stage()
        stage.session.selectTool(.highlight)
        stage.session.setColor(.amber)
        try stage.drag(from: point(50, 100), to: point(250, 100))

        let pixels = stage.pixels()
        // 40% of the colour: the screen below shows through.
        let amber = Pixel(.amber, alpha: MarkRenderer.highlightAlpha)
        #expect(amber.alpha == 102)
        #expect(stage.pixel(150, 100, in: pixels).isNear(amber))
        // Thick Highlight is 24 points wide, with flat ends.
        #expect(stage.pixel(150, 89, in: pixels).isNear(amber) && stage.pixel(150, 111, in: pixels).isNear(amber))
        #expect(stage.pixel(150, 86, in: pixels) == .clear && stage.pixel(150, 114, in: pixels) == .clear)
        #expect(stage.pixel(51, 100, in: pixels).isNear(amber) && stage.pixel(48, 100, in: pixels) == .clear)
    }

    @Test func row2_6_arrowIsALineWithAHeadAtTheEndOfTheDrag() throws {
        let stage = Stage()
        stage.session.selectTool(.arrow)
        // To the right: the head is 27 points long for the Thick size, so its base is at x 223.
        try stage.drag(from: point(50, 150), to: point(250, 150))
        // Up: the base of the head is at y 77.
        try stage.drag(from: point(350, 250), to: point(350, 50))

        let pixels = stage.pixels()
        let red = Pixel(.red)
        // The line is 7 points wide.
        #expect(stage.pixel(120, 150, in: pixels) == red)
        #expect(stage.pixel(120, 147.5, in: pixels) == red && stage.pixel(120, 152.5, in: pixels) == red)
        #expect(stage.pixel(120, 145, in: pixels) == .clear && stage.pixel(120, 155, in: pixels) == .clear)
        // The start is round.
        #expect(stage.pixel(48, 150, in: pixels) == red && stage.pixel(45, 150, in: pixels) == .clear)
        // The head is wide at its base and sharp at the end of the drag.
        #expect(stage.pixel(226, 141, in: pixels) == red && stage.pixel(226, 159, in: pixels) == red)
        #expect(stage.pixel(220, 141, in: pixels) == .clear)
        #expect(stage.pixel(246, 150, in: pixels) == red)
        #expect(stage.pixel(246, 141, in: pixels) == .clear && stage.pixel(246, 159, in: pixels) == .clear)
        #expect(stage.pixel(252, 150, in: pixels) == .clear)

        // The arrow that points up has the same shape, turned.
        #expect(stage.pixel(350, 180, in: pixels) == red)
        #expect(stage.pixel(345, 180, in: pixels) == .clear && stage.pixel(355, 180, in: pixels) == .clear)
        #expect(stage.pixel(350, 252, in: pixels) == red && stage.pixel(350, 255, in: pixels) == .clear)
        #expect(stage.pixel(341, 74, in: pixels) == red && stage.pixel(359, 74, in: pixels) == red)
        #expect(stage.pixel(350, 54, in: pixels) == red)
        #expect(stage.pixel(341, 54, in: pixels) == .clear && stage.pixel(350, 47, in: pixels) == .clear)
    }

    @Test func row2_7_rectangleAndEllipseAreOutlinesWithNoFill() throws {
        let stage = Stage()
        stage.session.setSize(.medium)
        stage.session.selectTool(.rectangle)
        try stage.drag(from: point(50, 50), to: point(150, 120))
        stage.session.selectTool(.ellipse)
        try stage.drag(from: point(300, 150), to: point(200, 50))

        let pixels = stage.pixels()
        let red = Pixel(.red)
        // The rectangle: its four sides are red, and its inside is clear.
        #expect(stage.pixel(50, 85, in: pixels) == red && stage.pixel(149.5, 85, in: pixels) == red)
        #expect(stage.pixel(100, 50, in: pixels) == red && stage.pixel(100, 119.5, in: pixels) == red)
        #expect(stage.pixel(50, 50, in: pixels) == red)
        #expect(stage.pixel(100, 85, in: pixels) == .clear)
        #expect(stage.pixel(56, 56, in: pixels) == .clear && stage.pixel(144, 114, in: pixels) == .clear)
        #expect(stage.pixel(44, 85, in: pixels) == .clear && stage.pixel(100, 126, in: pixels) == .clear)

        // The ellipse, from a drag to the top-left: its edge is red, and its inside and its corners are clear.
        #expect(stage.pixel(200, 100, in: pixels) == red && stage.pixel(299.5, 100, in: pixels) == red)
        #expect(stage.pixel(250, 50, in: pixels) == red && stage.pixel(250, 149.5, in: pixels) == red)
        #expect(stage.pixel(250, 100, in: pixels) == .clear)
        #expect(stage.pixel(204, 54, in: pixels) == .clear && stage.pixel(296, 146, in: pixels) == .clear)
    }

    @Test func row2_9_aSmallShapeLeavesNothingOnTheOverlay() throws {
        let stage = Stage()
        stage.session.selectTool(.rectangle)
        try stage.drag(from: point(100, 100), to: point(102, 103))
        #expect(stage.session.markCount == 0)
        #expect(stage.view.markLayers.isEmpty && stage.view.draftLayer.path == nil)
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)
    }

    @Test func row2_10_eachMarkKeepsItsSizeAndColour() throws {
        let stage = Stage()
        try stage.drag(from: point(50, 50), to: point(250, 50))
        stage.session.setColor(.blue)
        stage.session.setSize(.thin)
        try stage.drag(from: point(50, 100), to: point(250, 100))

        let pixels = stage.pixels()
        #expect(stage.pixel(150, 50, in: pixels) == Pixel(.red))
        #expect(stage.pixel(150, 47.5, in: pixels) == Pixel(.red))
        // The Thin pen is 2 points wide.
        #expect(stage.pixel(150, 100, in: pixels) == Pixel(.blue))
        #expect(stage.pixel(150, 97.5, in: pixels) == .clear)
    }

    @Test func row2_11_and2_14_undoAndClearAllTakeTheMarksOffTheOverlay() throws {
        let stage = Stage()
        try stage.drag(from: point(50, 50), to: point(250, 50))
        try stage.drag(from: point(50, 100), to: point(250, 100))
        stage.session.undo()
        var pixels = stage.pixels()
        #expect(stage.pixel(150, 50, in: pixels) == Pixel(.red) && stage.pixel(150, 100, in: pixels) == .clear)
        stage.session.redo()
        #expect(stage.pixel(150, 100, in: stage.pixels()) == Pixel(.red))

        stage.session.clearAll()
        #expect(stage.view.markLayers.isEmpty)
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)
        stage.session.undo()
        pixels = stage.pixels()
        #expect(stage.pixel(150, 50, in: pixels) == Pixel(.red) && stage.pixel(150, 100, in: pixels) == Pixel(.red))
    }

    // MARK: Text

    @Test func row2_8_aClickOpensATextFieldAndEnterMakesTheMark() throws {
        let stage = Stage()
        let view = stage.view
        stage.session.selectTool(.text)
        #expect(view.textView == nil)

        try stage.click(at: point(100, 100))
        let field = try #require(view.textView)
        #expect(field.superview === view)
        // The text starts 85 points below the top: the click at 100 is the middle of a line of
        // 30 points. The field goes to the right and the bottom edge of the screen.
        #expect(field.frame == CGRect(x: 100, y: 0, width: 300, height: 215))
        #expect(field.font?.pointSize == 24)
        #expect(field.textContainer?.size.width == 300 && field.textContainer?.lineFragmentPadding == 0)
        #expect(!field.drawsBackground)

        // Typing goes to the session. Return finishes the text.
        field.insertText("Hi", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(stage.session.textEdit?.text == "Hi")
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.textView == nil && field.superview == nil)
        let mark = try #require(stage.session.marks(on: stage.display.id).last?.mark)
        #expect(mark.tool == .text && mark.text == "Hi" && mark.points == [point(100, 85)] && mark.wrapWidth == 300)

        // The mark shows where the field showed the text: in the line of 30 points below y 85,
        // at the left of x 100, and nowhere else.
        let pixels = stage.pixels()
        #expect(pixels.inkCount(x: 200..<280, y: 170..<230) > 100)
        #expect(pixels.inkCount(x: 0..<800, y: 0..<600) == pixels.inkCount(x: 200..<280, y: 170..<230))
        // The letters are red.
        var redPixels = 0
        for y in 170..<230 {
            for x in 200..<280 where pixels[x, y] == Pixel(.red) { redPixels += 1 }
        }
        #expect(redPixels > 50)
    }

    @Test func row2_8_aFinishedTextIsUprightOnTheOverlay() throws {
        let stage = Stage()
        stage.session.selectTool(.text)
        try stage.click(at: point(100, 100))
        // A low line and a high mark: "_" has its ink at the bottom of the line, "'" at the top.
        stage.session.textChanged("_")
        try stage.click(at: point(200, 100))
        stage.session.textChanged("'")
        stage.session.completeText()

        // Each line box is 85 to 114 points from the top: pixels 170 to 228.
        let pixels = stage.pixels()
        #expect(pixels.inkCount(x: 200..<260, y: 170..<200) == 0)
        #expect(pixels.inkCount(x: 200..<260, y: 200..<232) > 20)
        #expect(pixels.inkCount(x: 400..<440, y: 170..<200) > 20)
        #expect(pixels.inkCount(x: 400..<440, y: 200..<232) == 0)
    }

    @Test func row2_8_aClickAtADifferentPlaceFinishesTheText() throws {
        let stage = Stage()
        let view = stage.view
        stage.session.selectTool(.text)
        try stage.click(at: point(100, 100))
        let first = try #require(view.textView)
        first.insertText("One", replacementRange: NSRange(location: NSNotFound, length: 0))

        try stage.click(at: point(200, 200))
        #expect(stage.session.marks(on: stage.display.id).map { $0.mark.text } == ["One"])
        // The next text is open at the new place, with a new field.
        let second = try #require(view.textView)
        #expect(second !== first && first.superview == nil)
        #expect(second.frame.origin.x == 200)

        // An empty text makes no mark.
        second.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.textView == nil && stage.session.markCount == 1)
    }

    @Test func row4_7_escInTheTextFieldCancelsOnlyTheText() throws {
        let stage = Stage()
        let view = stage.view
        try stage.drag(from: point(50, 50), to: point(250, 50))
        stage.session.selectTool(.text)
        try stage.click(at: point(100, 100))
        let field = try #require(view.textView)
        field.insertText("Not wanted", replacementRange: NSRange(location: NSNotFound, length: 0))

        field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(view.textView == nil)
        #expect(stage.session.mode == .drawing && stage.session.markCount == 1)
        // The second Esc has no text to cancel: it clears and stops (row 4.8).
        view.keyDown(with: try stage.key(53))
        #expect(stage.session.mode == .off && stage.session.markCount == 0)
    }

    @Test func row2_10_theOpenTextFieldGetsTheNewSizeAndColour() throws {
        let stage = Stage()
        stage.session.selectTool(.text)
        try stage.click(at: point(100, 100))
        let field = try #require(stage.view.textView)
        stage.session.setSize(.thin)
        stage.session.setColor(.green)
        #expect(stage.view.textView === field)
        #expect(field.font?.pointSize == 14)
        #expect(field.textColor == NSColor(cgColor: MarkRenderer.color(.green)))
    }

    // MARK: The keys

    @Test func row1_10_theKeysStopAtTheOverlay() throws {
        let stage = Stage()
        let view = stage.view
        try stage.drag(from: point(50, 50), to: point(250, 50))
        try stage.drag(from: point(50, 100), to: point(250, 100))
        #expect(view.acceptsFirstResponder)

        // A letter, Return and Space do nothing. The view does not hand them on, so they do not
        // reach the app below and they do not beep.
        view.keyDown(with: try stage.key(0, "a"))
        view.keyDown(with: try stage.key(36, "\r"))
        view.keyDown(with: try stage.key(49, " "))
        #expect(stage.session.mode == .drawing && stage.session.markCount == 2)

        // Command-Z is Undo and Shift-Command-Z is Redo (rows 2.11 and 2.12).
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(stage.session.markCount == 1)
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: [.command, .shift])))
        #expect(stage.session.markCount == 2)
        // A different Command key is not for the overlay.
        #expect(!view.performKeyEquivalent(with: try stage.key(1, "s", flags: .command)))
        #expect(!view.performKeyEquivalent(with: try stage.key(6, "z", flags: [.command, .control])))
        #expect(stage.session.markCount == 2)

        // Esc clears each mark and turns drawing off (row 4.8).
        view.keyDown(with: try stage.key(53))
        #expect(stage.session.mode == .off && stage.session.markCount == 0)
        #expect(view.markLayers.isEmpty)
    }

    // MARK: Fade

    @Test func row3_3_aFadeMarkGetsWeakerOnTheOverlayAndThenGoesAway() throws {
        let stage = Stage()
        stage.session.setStay(.fade)
        try stage.drag(from: point(50, 100), to: point(250, 100))
        #expect(stage.pixel(150, 100, in: stage.pixels()) == Pixel(.red))

        stage.clock.time += 1.5
        stage.session.tick()
        stage.view.refreshOpacities()
        #expect(stage.pixel(150, 100, in: stage.pixels()).isNear(Pixel(.red, alpha: 0.5)))

        stage.clock.time += 0.5
        stage.session.tick()
        #expect(stage.view.markLayers.isEmpty)
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)
    }

    @Test func row3_11_aMarkThatUndoBringsBackIsAtFullStrengthAgain() throws {
        let stage = Stage()
        stage.session.setStay(.fade)
        try stage.drag(from: point(50, 100), to: point(250, 100))
        stage.clock.time += 1.75
        stage.view.refreshOpacities()
        stage.session.clearAll()

        stage.clock.time += 30
        stage.session.undo()
        #expect(stage.pixel(150, 100, in: stage.pixels()) == Pixel(.red))
    }
}
