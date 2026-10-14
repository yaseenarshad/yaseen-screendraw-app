import AppKit
import Carbon.HIToolbox
@testable import ScreendrawKit
import Testing

/// The Line tool, the Stamp tool and Shift for straight shapes (D15, YAZ-2829), out of sight:
/// rows 2.50 to 2.61. The tests use the session with no window, the toolbar view, and the overlay
/// view with events that the test makes. No test shows a window, moves the mouse or presses a key.
@MainActor @Suite struct NewToolsTests {
    private let left = Screens.left.id
    private let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
    private let black = Pixel(red: 0, green: 0, blue: 0, alpha: 255)

    /// One drag with Shift down from the pointer down to the release. Returns the points of the mark.
    private func shiftDrag(_ tool: Tool, _ points: [CGPoint], in session: DrawSession) -> [CGPoint]? {
        let count = session.markCount
        session.selectTool(tool)
        session.setShift(true)
        session.drag(points)
        session.setShift(false)
        return session.markCount > count ? session.marks(on: left).last?.mark.points : nil
    }

    private func isNear(_ a: CGPoint?, _ b: CGPoint) -> Bool {
        a.map { abs($0.x - b.x) < 0.0001 && abs($0.y - b.y) < 0.0001 } ?? false
    }

    /// The stamps of the two test screens, as their numbers.
    private func numbers(_ session: DrawSession) -> [Int] {
        session.allMarks.filter { $0.mark.tool == .stamp }.map { $0.mark.number }
    }

    // MARK: The toolbar

    @Test func row2_50_theToolsAreInTheApprovedOrder() throws {
        let names = ["Select", "Pen", "Highlight", "Line", "Arrow", "Rectangle", "Ellipse", "Text", "Stamp"]
        #expect(Tool.allCases.map { $0.name } == names)
        // The toolbar has the nine tool buttons in this order: each one is after the one before
        // it, to its right or below it. No two overlap.
        let stage = ToolbarTests.Stage()
        let frames = try names.map { try stage.button($0).frame }
        for (before, after) in zip(frames, frames.dropFirst()) {
            #expect(before.maxX <= after.minX || before.maxY <= after.minY)
        }
        // Each tool has a picture of the system, not the first letter of its name.
        for name in names {
            #expect(try stage.button(name).image?.accessibilityDescription == name, "\(name)")
        }
        for symbol in ["arrow.up.and.down.and.arrow.left.and.right", "line.diagonal", "1.circle.fill"] {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
        // Each button selects its tool, and the settings list the tools in the same order.
        for tool in Tool.allCases {
            try stage.press(tool.name)
            #expect(stage.session.tool == tool)
        }
        #expect(ToolbarAction.groups.first?.actions == Tool.allCases.map { ToolbarAction.tool($0) })
        try Snapshot(of: stage.toolbar, scale: 2).write("v020-toolbar.png")
    }

    // MARK: Line

    @Test func row2_51_lineIsAStraightLineWithNoHeadAndItsKeysAreDAndL() throws {
        let stage = OverlayViewTests.Stage()
        let session = stage.session
        // D is the key of the Line at the start.
        #expect(ToolbarAction.tool(.line).startKey == "d")
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_D), "d"))
        #expect(session.tool == .line)

        // A drag with many pointer moves: the mark is the start and the end of the drag.
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, 100, 150))
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 150, 250))
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 200, 100))
        #expect(session.draft(on: stage.display.id)?.points == [point(100, 150), point(200, 100)])
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 300, 150))
        stage.view.mouseUp(with: try stage.mouse(.leftMouseUp, 300, 150))
        let mark = try #require(session.marks(on: stage.display.id).last?.mark)
        #expect(mark.tool == .line && mark.points == [point(100, 150), point(300, 150)])
        #expect(mark.style == MarkStyle(color: .red, size: .thick))

        // The Thick line is 7 points wide from the start to the end. It has no head: at its end
        // it is as wide as in its middle. An Arrow is 24 points wide there.
        let pixels = stage.pixels()
        for x in [100, 200, 280, 296, 299.5] as [CGFloat] {
            #expect(stage.pixel(x, 150, in: pixels) == Pixel(.red), "x \(x)")
            #expect(stage.pixel(x, 147, in: pixels) == Pixel(.red) && stage.pixel(x, 153, in: pixels) == Pixel(.red), "x \(x)")
            #expect(stage.pixel(x, 145.5, in: pixels) == .clear && stage.pixel(x, 154, in: pixels) == .clear, "x \(x)")
        }
        // The two ends are round, and nothing is beyond them.
        #expect(stage.pixel(98, 150, in: pixels) == Pixel(.red) && stage.pixel(302, 150, in: pixels) == Pixel(.red))
        #expect(stage.pixel(95, 150, in: pixels) == .clear && stage.pixel(305, 150, in: pixels) == .clear)
        #expect(pixels.inkCount(x: 0..<800, y: 0..<600) == pixels.inkCount(x: 190..<610, y: 292..<308))

        // L also selects the Line while no action uses L. The draw app has D and L.
        session.selectTool(.pen)
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_L), "l"))
        #expect(session.tool == .line)
        session.selectTool(.pen)
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_L), "L", flags: .shift))
        #expect(session.tool == .line)
        // L is not the key of an action, so an action can take it. Then L is the key of that action only.
        #expect(session.toolbarKeys.all.values.contains("l") == false)
        session.toolbarKeys.set("l", for: .tool(.highlight))
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_L), "l"))
        #expect(session.tool == .highlight)
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_D), "d"))
        #expect(session.tool == .line)
        // The Line gets a different key: L is still its second key while no action has it.
        session.toolbarKeys.reset()
        session.toolbarKeys.set("x", for: .tool(.line))
        session.selectTool(.pen)
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_L), "l"))
        #expect(session.tool == .line)
    }

    @Test func row2_52_aLineShorterThan4PointsMakesNoMark() {
        let session = Fixture().session
        session.selectTool(.line)
        #expect(DrawSession.minimumShape == 4)
        // A click, and drags of less than 4 points in each direction.
        session.click(at: point(100, 100))
        session.drag([point(100, 100), point(103.9, 100)])
        session.drag([point(100, 100), point(100, 97)])
        session.drag([point(100, 100), point(102.8, 102.8)])
        #expect(session.markCount == 0 && !session.canUndo && session.draft(on: left) == nil)
        // 4 points make a mark, also on the diagonal.
        session.drag([point(100, 100), point(104, 100)])
        session.drag([point(200, 100), point(202.9, 102.9)])
        #expect(session.marks(on: left).map { $0.mark.tool } == [.line, .line])
        // A long drag that comes back to its start makes no mark.
        session.drag([point(300, 300), point(500, 500), point(301, 301)])
        #expect(session.markCount == 2)
    }

    // MARK: Shift

    @Test func row2_53_shiftWithPenOrHighlightMakesOneStraightLineFromTheStartToThePointer() throws {
        let session = Fixture().session
        for tool in [Tool.pen, .highlight] {
            session.selectTool(tool)
            session.setShift(true)
            session.pointerDown(at: point(100, 100), on: left)
            session.pointerDragged(to: point(150, 180))
            session.pointerDragged(to: point(220, 90))
            // During the drag the mark is one line from the start to the pointer.
            #expect(session.draft(on: left)?.points == [point(100, 100), point(220, 90)], "\(tool)")
            session.pointerDragged(to: point(300, 160))
            session.pointerUp(at: point(300, 160))
            session.setShift(false)
            let mark = try #require(session.marks(on: left).last?.mark)
            #expect(mark.tool == tool && mark.points == [point(100, 100), point(300, 160)], "\(tool)")
        }
        // With no Shift, the mark has each point of the pointer.
        session.selectTool(.pen)
        session.drag([point(100, 300), point(150, 380), point(220, 290)])
        #expect(session.marks(on: left).last?.mark.points == [point(100, 300), point(150, 380), point(220, 290)])
        // A Pen click with Shift is still a dot.
        #expect(shiftDrag(.pen, [point(400, 400)], in: session) == [point(400, 400)])
        #expect(shiftDrag(.highlight, [point(450, 400)], in: session) == nil)

        // The straight Pen line on the overlay: red along the line, and nothing at the corner of the hand.
        let stage = OverlayViewTests.Stage()
        let flags = NSEvent.ModifierFlags.shift
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, at: point(50, 100), flags: flags))
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(150, 200), flags: flags))
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(250, 100), flags: flags))
        var pixels = stage.pixels()
        #expect(stage.pixel(150, 100, in: pixels) == Pixel(.red) && stage.pixel(150, 200, in: pixels) == .clear)
        stage.view.mouseUp(with: try stage.mouse(.leftMouseUp, at: point(250, 100), flags: flags))
        pixels = stage.pixels()
        #expect(stage.session.marks(on: stage.display.id).map { $0.mark.points } == [[point(50, 100), point(250, 100)]])
        #expect(stage.pixel(150, 100, in: pixels) == Pixel(.red) && stage.pixel(150, 200, in: pixels) == .clear)
        #expect(pixels.inkCount(x: 0..<800, y: 0..<600) == pixels.inkCount(x: 90..<510, y: 192..<208))
    }

    @Test func row2_54_shiftWithLineOrArrowGoesInStepsOf45Degrees() throws {
        let session = Fixture().session
        let diagonal = CGFloat(0.5).squareRoot()
        for tool in [Tool.line, .arrow] {
            // The pointer is near to an axis: the mark is exactly on that axis, with the length of the drag.
            #expect(shiftDrag(tool, [point(300, 300), point(400, 310)], in: session) == [point(300, 300), point(300 + hypot(100, 10), 300)])
            #expect(shiftDrag(tool, [point(300, 300), point(290, 400)], in: session) == [point(300, 300), point(300, 300 + hypot(10, 100))])
            #expect(shiftDrag(tool, [point(300, 300), point(200, 295)], in: session) == [point(300, 300), point(300 - hypot(100, 5), 300)])
            #expect(shiftDrag(tool, [point(300, 300), point(305, 200)], in: session) == [point(300, 300), point(300, 300 - hypot(5, 100))])
            // The pointer is near to a diagonal: the mark is on that diagonal.
            for (dx, dy, signX, signY) in [(90, 110, 1, 1), (-110, 90, -1, 1), (-90, -110, -1, -1), (110, -90, 1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                let length = hypot(dx, dy)
                let end = shiftDrag(tool, [point(300, 300), point(300 + dx, 300 + dy)], in: session)?.last
                #expect(isNear(end, point(300 + signX * length * diagonal, 300 + signY * length * diagonal)), "\(tool) \(dx) \(dy)")
            }
            // Each angle of the pointer gives one of the eight directions.
            for degrees in stride(from: 0, to: 360, by: 7) {
                let angle = CGFloat(degrees) * .pi / 180
                let points = try #require(shiftDrag(tool, [point(300, 300), point(300 + 100 * cos(angle), 300 + 100 * sin(angle))], in: session))
                let step = atan2(points[1].y - points[0].y, points[1].x - points[0].x) / (.pi / 4)
                #expect(abs(step - step.rounded()) < 0.0001, "\(tool) at \(degrees) degrees")
                #expect(abs(step.rounded() - (angle / (.pi / 4)).rounded()).truncatingRemainder(dividingBy: 8) == 0, "\(tool) at \(degrees) degrees")
                #expect(abs(hypot(points[1].x - points[0].x, points[1].y - points[0].y) - 100) < 0.0001)
            }
        }
        // At an edge of the screen the line gets shorter, and its angle stays. The Thick line stops 3.5 points before the edge.
        let end = try #require(shiftDrag(.line, [point(700, 500), point(1000, 790)], in: session)?.last)
        #expect(isNear(end, point(796.5, 596.5)))
        #expect(shiftDrag(.line, [point(700, 500), point(5000, 510)], in: session) == [point(700, 500), point(796.5, 500)])
        // With no Shift, the line goes to the pointer.
        session.selectTool(.line)
        session.drag([point(300, 300), point(400, 310)])
        #expect(session.marks(on: left).last?.mark.points == [point(300, 300), point(400, 310)])
        // A short drag with Shift makes no mark (row 2.52).
        #expect(shiftDrag(.line, [point(300, 300), point(302, 302)], in: session) == nil)
    }

    @Test func row2_55_shiftWithRectangleOrEllipseMakesASquareOrACircle() throws {
        let session = Fixture().session
        for tool in [Tool.rectangle, .ellipse] {
            // The longer side of the drag is the side of the square, in each of the four directions.
            #expect(shiftDrag(tool, [point(300, 300), point(400, 350)], in: session) == [point(300, 300), point(400, 400)])
            #expect(shiftDrag(tool, [point(300, 300), point(340, 420)], in: session) == [point(300, 300), point(420, 420)])
            #expect(shiftDrag(tool, [point(300, 300), point(200, 320)], in: session) == [point(300, 300), point(200, 400)])
            #expect(shiftDrag(tool, [point(300, 300), point(250, 180)], in: session) == [point(300, 300), point(180, 180)])
            #expect(shiftDrag(tool, [point(300, 300), point(380, 240)], in: session) == [point(300, 300), point(380, 220)])
            let mark = try #require(session.marks(on: left).last?.mark)
            #expect(mark.tool == tool && mark.frame.width == mark.frame.height)
            // At an edge of the screen the square stops, and it stays a square.
            #expect(shiftDrag(tool, [point(700, 300), point(5000, 320)], in: session) == [point(700, 300), point(796.5, 396.5)])
            #expect(shiftDrag(tool, [point(300, 50), point(400, -900)], in: session) == [point(300, 50), point(346.5, 3.5)])
        }
        // With no Shift, the shape has the two sides of the drag.
        session.selectTool(.ellipse)
        session.drag([point(300, 300), point(400, 350)])
        #expect(session.marks(on: left).last?.mark.points == [point(300, 300), point(400, 350)])

        // The circle on the overlay: the drag is 100 by 40 points, and the Ellipse is 100 by 100 points.
        let stage = OverlayViewTests.Stage()
        stage.session.selectTool(.ellipse)
        let flags = NSEvent.ModifierFlags.shift
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, at: point(100, 100), flags: flags))
        stage.view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(200, 140), flags: flags))
        stage.view.mouseUp(with: try stage.mouse(.leftMouseUp, at: point(200, 140), flags: flags))
        let pixels = stage.pixels()
        // The four ends of the two diameters are on the line, and the middle is empty.
        for (x, y) in [(100, 150), (200, 150), (150, 100), (150, 200)] as [(CGFloat, CGFloat)] {
            #expect(stage.pixel(x, y, in: pixels) == Pixel(.red), "\(x), \(y)")
        }
        #expect(stage.pixel(150, 150, in: pixels) == .clear && stage.pixel(104, 104, in: pixels) == .clear)
    }

    @Test func row2_56_shiftInTheMiddleOfADragChangesTheMarkAtOnce() throws {
        let stage = OverlayViewTests.Stage()
        let view = stage.view, session = stage.session, id = stage.display.id
        func shift(_ isDown: Bool) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: isDown ? .shift : [], timestamp: 0, windowNumber: 0,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_Shift)
            ))
        }

        // A Rectangle: the drag is 150 by 50 points.
        session.selectTool(.rectangle)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 100, 100))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 250, 150))
        #expect(session.draft(on: id)?.points == [point(100, 100), point(250, 150)])
        #expect(stage.pixel(175, 150, in: stage.pixels()) == Pixel(.red))

        // Shift goes down with no move of the pointer: the mark is a square at once, on the overlay too.
        var changes = 0
        let show = session.onChange
        session.onChange = {
            changes += 1
            show?()
        }
        view.flagsChanged(with: try shift(true))
        #expect(changes == 1)
        #expect(session.draft(on: id)?.points == [point(100, 100), point(250, 250)])
        var pixels = stage.pixels()
        #expect(stage.pixel(175, 250, in: pixels) == Pixel(.red) && stage.pixel(175, 150, in: pixels) == .clear)
        // Shift goes up: the mark is the rectangle of the drag again.
        view.flagsChanged(with: try shift(false))
        #expect(changes == 2)
        #expect(session.draft(on: id)?.points == [point(100, 100), point(250, 150)])
        pixels = stage.pixels()
        #expect(stage.pixel(175, 150, in: pixels) == Pixel(.red) && stage.pixel(175, 250, in: pixels) == .clear)
        // A second event with the same state of Shift changes nothing.
        view.flagsChanged(with: try shift(false))
        #expect(changes == 2)
        // The release with Shift down gives the square.
        view.flagsChanged(with: try shift(true))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, at: point(250, 150), flags: .shift))
        #expect(session.marks(on: id).map { $0.mark.points } == [[point(100, 100), point(250, 250)]])
        view.flagsChanged(with: try shift(false))

        // A Pen line: Shift makes it straight, and without Shift it has each point of the hand again.
        session.selectTool(.pen)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 270, 280))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 310, 200))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 350, 280))
        // The line of the hand goes up to the left of x 310, 227 points from the top.
        #expect(stage.pixel(310, 227, in: stage.pixels()) == Pixel(.red))
        view.flagsChanged(with: try shift(true))
        #expect(session.draft(on: id)?.points == [point(270, 280), point(350, 280)])
        pixels = stage.pixels()
        #expect(stage.pixel(310, 280, in: pixels) == Pixel(.red) && stage.pixel(310, 227, in: pixels) == .clear)
        // The pointer moves with Shift down, and then Shift goes up.
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(390, 200), flags: .shift))
        #expect(session.draft(on: id)?.points == [point(270, 280), point(390, 200)])
        view.flagsChanged(with: try shift(false))
        #expect(session.draft(on: id)?.points == [point(270, 280), point(310, 200), point(350, 280), point(390, 200)])
        pixels = stage.pixels()
        #expect(stage.pixel(310, 280, in: pixels) == .clear && stage.pixel(310, 227, in: pixels) == Pixel(.red))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 390, 200))
        #expect(session.marks(on: id).last?.mark.points == [point(270, 280), point(310, 200), point(350, 280), point(390, 200)])

        // The mouse events also tell the state of Shift, for a window that does not have the keyboard.
        session.selectTool(.line)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, at: point(300, 50), flags: .shift))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(350, 55), flags: .shift))
        #expect(session.draft(on: id)?.points.last?.y == 50)
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, at: point(350, 55)))
        #expect(session.draft(on: id)?.points.last == point(350, 55))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, at: point(350, 55)))
        // Shift with no drag changes nothing, and it is no toolbar key.
        let revision = session.marksRevision
        view.flagsChanged(with: try shift(true))
        view.flagsChanged(with: try shift(false))
        #expect(session.marksRevision == revision && session.tool == .line && session.draft(on: id) == nil)
    }

    // MARK: Stamp

    @Test func row2_57_aClickPutsAFilledCircleWithANumberThatIsEasyToRead() throws {
        // N is the key of the Stamp at the start.
        let keys = OverlayViewTests.Stage()
        #expect(ToolbarAction.tool(.stamp).startKey == "n")
        keys.view.keyDown(with: try keys.key(UInt16(kVK_ANSI_N), "n"))
        #expect(keys.session.tool == .stamp)
        // The pointer down puts the stamp. A drag after it draws nothing more.
        keys.view.mouseDown(with: try keys.mouse(.leftMouseDown, 100, 100))
        #expect(keys.session.markCount == 1 && keys.session.draft(on: keys.display.id) == nil)
        keys.view.mouseDragged(with: try keys.mouse(.leftMouseDragged, 200, 200))
        keys.view.mouseUp(with: try keys.mouse(.leftMouseUp, 200, 200))
        let first = try #require(keys.session.marks(on: keys.display.id).first)
        #expect(keys.session.markCount == 1 && first.mark.tool == .stamp && first.mark.points == [point(100, 100)])
        #expect(first.mark.number == 1 && first.mark.style == MarkStyle(color: .red, size: .thick) && first.stay == .sticky)
        // Near an edge, the full circle stays on the screen.
        try keys.click(at: point(2, 299))
        #expect(keys.session.marks(on: keys.display.id).last?.mark.points == [point(20, 280)])

        // The size follows Thin, Medium, Thick.
        #expect(MarkSize.allCases.map { MarkStyle(color: .red, size: $0).stampDiameter } == [22, 30, 40])

        // Each colour and each size on the overlay: a filled circle in the colour, with the number in it.
        for scale in [2, 1] as [CGFloat] {
            for size in MarkSize.allCases {
                for color in MarkColor.allCases {
                    let stage = OverlayViewTests.Stage(scale: scale)
                    stage.session.selectTool(.stamp)
                    stage.session.setColor(color)
                    stage.session.setSize(size)
                    try stage.click(at: point(200, 150))
                    let pixels = stage.pixels()
                    let radius = MarkStyle(color: color, size: size).stampDiameter / 2
                    let what: Comment = "\(color.name) \(size.name) at scale \(Int(scale))"

                    // The circle is filled with the colour, to its edge, and nothing is outside it.
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] as [(CGFloat, CGFloat)] {
                        #expect(stage.pixel(200 + dx * (radius - 1.5), 150 + dy * (radius - 1.5), in: pixels) == Pixel(color), what)
                        #expect(stage.pixel(200 + dx * (radius + 1), 150 + dy * (radius + 1), in: pixels) == .clear, what)
                    }
                    #expect(stage.pixel(200 + radius * 0.8, 150 + radius * 0.8, in: pixels) == .clear, what)
                    // The number is white on red, blue and black, and black on amber, green and white.
                    let ink = [MarkColor.red, .blue, .black].contains(color) ? white : black
                    #expect(Pixel(MarkColor.white) == white && Pixel(MarkColor.black) == black)
                    var digit = 0, circle = 0, other = 0
                    var digitX: [Int] = [], digitY: [Int] = []
                    for y in Int((150 - radius) * scale)..<Int((150 + radius) * scale) {
                        for x in Int((200 - radius) * scale)..<Int((200 + radius) * scale) {
                            let pixel = pixels[x, y]
                            if pixel == ink {
                                digit += 1
                                digitX.append(x)
                                digitY.append(y)
                            } else if pixel == Pixel(color) {
                                circle += 1
                            } else if pixel.alpha == 255 {
                                other += 1
                            }
                        }
                    }
                    // The digit "1" has pixels in its own colour, and the circle is most of the area.
                    // The pixels at the edge of the digit are between the two colours.
                    let area = Int(CGFloat.pi * radius * radius * scale * scale)
                    #expect(digit >= 8, "\(what): the digit has \(digit) pixels in its own colour")
                    #expect(digit + other > area / 20 && digit + other < area / 3, "\(what): the digit has \(digit + other) of \(area) pixels")
                    #expect(circle > area / 2, what)
                    // The digit is in the middle of the circle, and it is about half as high as the circle.
                    let midX = CGFloat(try #require(digitX.min()) + (try #require(digitX.max())) + 1) / 2 / scale
                    let midY = CGFloat(try #require(digitY.min()) + (try #require(digitY.max())) + 1) / 2 / scale
                    let height = CGFloat(try #require(digitY.max()) - (try #require(digitY.min())) + 1) / scale
                    #expect(abs(midX - 200) <= 1.5 && abs(midY - 150) <= 1.5, "\(what): the middle of the digit is \(midX), \(midY)")
                    #expect(height > radius * 0.6 && height < radius * 1.2, "\(what): the digit is \(height) points high")

                    // The number is easy to read: the contrast of its colour with the colour of the
                    // circle is 3 or more (the WCAG value for large bold text).
                    let number = try #require(MarkRenderer.numberColor(on: color).components?.first)
                    #expect(contrast(of: color, withGray: number) >= 3, "\(color.name) has the contrast \(contrast(of: color, withGray: number))")
                }
            }
        }
    }

    /// The WCAG contrast of a mark colour with a grey (0 is black, 1 is white).
    private func contrast(of color: MarkColor, withGray gray: CGFloat) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let parts = color.components
        let luminance = 0.2126 * linear(parts.red) + 0.7152 * linear(parts.green) + 0.0722 * linear(parts.blue)
        let other = linear(gray)
        return (max(luminance, other) + 0.05) / (min(luminance, other) + 0.05)
    }

    @Test func row2_58_theNextStampHasTheHighestNumberOfAllScreensPlus1() throws {
        let fixture = Fixture()
        let session = fixture.session
        session.selectTool(.stamp)
        // With no stamp, it is 1.
        session.click(at: point(100, 100))
        session.click(at: point(200, 100))
        #expect(numbers(session) == [1, 2])
        // The stamps of all screens count.
        session.click(at: point(100, 100), on: Screens.right.id)
        session.click(at: point(300, 100))
        #expect(session.marks(on: left).map { $0.mark.number } == [1, 2, 4])
        #expect(session.marks(on: Screens.right.id).map { $0.mark.number } == [3])
        // A mark of a different tool has no number, and it does not count.
        session.draw(.pen, [point(100, 300), point(300, 300)])
        session.draw(.rectangle, [point(400, 300), point(500, 400)])
        session.selectTool(.stamp)
        session.click(at: point(400, 100))
        #expect(numbers(session).max() == 5 && session.allMarks.filter { $0.mark.tool != .stamp }.allSatisfy { $0.mark.number == 0 })

        // The highest number counts, not the number of stamps: after a delete of stamp 2, the next is 6.
        session.selectTool(.select)
        session.click(at: point(200, 100))
        session.delete()
        session.selectTool(.stamp)
        session.click(at: point(500, 100))
        #expect(session.marks(on: left).filter { $0.mark.tool == .stamp }.map { $0.mark.number } == [1, 4, 5, 6])
        // After a delete of the highest stamp, its number is free again.
        session.selectTool(.select)
        session.click(at: point(500, 100))
        session.delete()
        session.selectTool(.stamp)
        session.click(at: point(600, 100))
        #expect(numbers(session).max() == 6 && numbers(session).filter { $0 == 6 }.count == 1)

        // Nothing is stored: the app writes no number to its settings.
        #expect(Set(fixture.store.values.keys) == ["drawTool"])
        // The Sticky stamps that the app keeps while drawing is off still count (row 4.6).
        session.stop()
        session.start(displays: [Screens.left, Screens.right])
        session.click(at: point(700, 100))
        #expect(numbers(session).max() == 7)
        // A change of the size or the colour, and a move, do not change the number of a stamp.
        session.selectTool(.select)
        session.click(at: point(700, 100))
        session.setColor(.blue)
        session.setSize(.thin)
        session.drag([point(700, 100), point(700, 300)])
        let moved = try #require(session.marks(on: left).last?.mark)
        #expect(moved.number == 7 && moved.points == [point(700, 300)] && moved.style == MarkStyle(color: .blue, size: .thin))
    }

    @Test func row2_59_afterClearAllEscOrUndoTheRuleGivesTheNextNumber() {
        let session = Fixture().session
        session.selectTool(.stamp)
        for x in [100, 200, 300] as [CGFloat] { session.click(at: point(x, 100)) }
        #expect(numbers(session) == [1, 2, 3])

        // Undo of a stamp: its number is free, and the next stamp gets it.
        session.undo()
        #expect(numbers(session) == [1, 2])
        session.click(at: point(400, 100))
        #expect(numbers(session) == [1, 2, 3])
        // Undo and then Redo bring the same stamp back with its number.
        session.undo()
        session.undo()
        session.redo()
        session.redo()
        #expect(numbers(session) == [1, 2, 3])

        // After Clear all, the next stamp is 1.
        session.clearAll()
        session.click(at: point(100, 300))
        #expect(numbers(session) == [1])
        // Undo of that stamp and of the clear brings the three stamps back. The next stamp is 4.
        session.undo()
        session.undo()
        #expect(numbers(session) == [1, 2, 3])
        session.click(at: point(500, 100))
        #expect(numbers(session) == [1, 2, 3, 4])

        // Delete with no selection clears all (row 2.20): the next stamp is 1.
        session.delete()
        session.click(at: point(100, 300))
        #expect(numbers(session) == [1])

        // Esc removes no stamp (row 4.41). Back in mode drawing, the next stamp is 2.
        session.escape()
        #expect(session.mode == .clickThrough && numbers(session) == [1])
        session.toggleClickThrough()
        session.click(at: point(100, 100))
        #expect(numbers(session) == [1, 2])
    }

    @Test func row2_60_aStampWithFadeOrHoldFadesAndThenItsNumberIsFreeAgain() throws {
        let fixture = Fixture()
        let session = fixture.session
        session.selectTool(.stamp)
        session.click(at: point(100, 100))
        // A Fade stamp: full strength for 1 second, then it fades for 1 second, as each other mark.
        session.setStay(.fade)
        session.click(at: point(200, 100))
        let fade = try #require(session.marks(on: left).last)
        #expect(fade.mark.number == 2 && fade.stay == .fade && session.hasTimedMarks)
        fixture.clock.time += 1
        #expect(session.opacity(of: fade) == 1)
        fixture.clock.time += 0.5
        #expect(session.opacity(of: fade) == 0.5)
        // While it is visible, its number is not free.
        session.setStay(.sticky)
        session.click(at: point(300, 100))
        #expect(numbers(session) == [1, 2, 3])
        fixture.clock.time += 0.5
        session.tick()
        #expect(numbers(session) == [1, 3])

        // Hold stamps fade together 5 seconds after the last drawing activity.
        session.setStay(.hold)
        session.click(at: point(400, 100))
        session.click(at: point(500, 100))
        #expect(numbers(session) == [1, 3, 4, 5])
        fixture.clock.time += 5.5
        #expect(session.marks(on: left).filter { $0.stay == .hold }.map { session.opacity(of: $0) } == [0.5, 0.5])
        fixture.clock.time += 0.5
        session.tick()
        #expect(numbers(session) == [1, 3] && !session.hasTimedMarks)
        // The numbers 4 and 5 are free again: the next stamp is 4.
        session.setStay(.sticky)
        session.click(at: point(600, 100))
        #expect(numbers(session) == [1, 3, 4])

        // The stamp gets weaker on the overlay with its number: the circle and the digit fade together.
        let stage = OverlayViewTests.Stage()
        stage.session.selectTool(.stamp)
        stage.session.setStay(.fade)
        try stage.click(at: point(200, 150))
        #expect(stage.pixel(185, 150, in: stage.pixels()) == Pixel(.red))
        stage.clock.time += 1.5
        stage.session.tick()
        stage.view.refreshOpacities()
        #expect(stage.pixel(185, 150, in: stage.pixels()).isNear(Pixel(.red, alpha: 0.5)))
        #expect(stage.pixel(200, 142, in: stage.pixels()).alpha < 200)
        stage.clock.time += 0.5
        stage.session.tick()
        #expect(stage.pixels().inkCount(x: 0..<800, y: 0..<600) == 0)
    }

    // MARK: Settings

    @Test func row2_61_theToolbarKeysInSettingsListTheNewTools() throws {
        let stage = ToolbarKeysTests.Stage(isOn: false)
        // There are 21 actions: nine tools, three sizes, six colours and three stay values.
        #expect(ToolbarAction.all.count == 21 && ToolbarAction.groups.map { $0.actions.count } == [9, 3, 6, 3])
        #expect(ToolbarAction.groups.first?.actions.map { $0.name } == ["Select", "Pen", "Highlight", "Line", "Arrow", "Rectangle", "Ellipse", "Text", "Stamp"])
        // Select (V), Line (D) and Stamp (N).
        let new: [(action: ToolbarAction, key: String, id: String)] = [
            (.tool(.select), "v", "tool.select"), (.tool(.line), "d", "tool.line"), (.tool(.stamp), "n", "tool.stamp"),
        ]
        for (action, key, id) in new {
            #expect(stage.settings.toolbarKey(action) == key && action.startKey == key && action.id == id)
        }
        // No two of the 21 start keys are the same, and the second keys P and L are free.
        #expect(Set(ToolbarAction.all.map { $0.startKey }).count == 21)
        #expect(!ToolbarAction.all.map { $0.startKey }.contains("p") && !ToolbarAction.all.map { $0.startKey }.contains("l"))

        // Each new key can be changed, it works at once, and the toolbar shows it (row 5.23).
        stage.controller.toggleDrawing()
        #expect(stage.record("x", for: .tool(.stamp)))
        #expect(stage.settings.toolbarKey(.tool(.stamp)) == "x" && stage.settings.toolbarKeyProblem == nil)
        #expect(try stage.toolbar.button(named: "Stamp").key == "X")
        try stage.type("x")
        #expect(stage.session.tool == .stamp)
        try stage.type("w")
        try stage.type("n")
        #expect(stage.session.tool == .pen)
        // The key of a new tool belongs to it: a different action cannot take it (row 5.22).
        #expect(stage.record("v", for: .tool(.pen)))
        #expect(stage.settings.toolbarKeyProblem == "The key V belongs to Select.")
        #expect(stage.record("d", for: .color(.red)))
        #expect(stage.settings.toolbarKeyProblem == "The key D belongs to Line.")
        // The reset gives the three new tools their start keys again (row 5.24).
        stage.settings.resetToolbarKeys()
        #expect(stage.shownKeys == "vwhdarotn123456789fgs")
        // The stored table has the 21 actions.
        #expect(stage.record("x", for: .tool(.select)))
        #expect((stage.defaults.object(forKey: "toolbarKeys") as? [String: String])?.count == 21)

        // A table that version 0.1.3 stored has 18 actions. The three new tools get their start keys.
        let old = MemoryDefaults()
        old.set(["tool.pen": "x", "tool.arrow": "z"], forKey: "toolbarKeys")
        #expect(ToolbarAction.all.map { ToolbarKeys(defaults: old).all[$0] ?? "?" }.joined() == "vxhdzrotn123456789fgs")
    }
}
