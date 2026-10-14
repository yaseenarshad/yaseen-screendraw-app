import AppKit
@testable import ScreendrawKit
import Testing

/// Fixed screens for the toolbar. They are larger than the screens of `Screens`, so one row and
/// one column fit on the large ones. No test uses a real screen.
enum Desks {
    /// A small laptop: 1280 by 800. One column does not fit in its visible part of 705 points.
    static let small = screen(31, CGRect(x: 0, y: 0, width: 1280, height: 800), dock: 70)
    /// 1920 by 1080, with a menu bar and a Dock.
    static let main = screen(32, CGRect(x: 0, y: 0, width: 1920, height: 1080), dock: 70)
    /// At the right of `main`: 2560 by 1440, with a menu bar and no Dock.
    static let side = screen(33, CGRect(x: 1920, y: 0, width: 2560, height: 1440), dock: 0)
    /// A screen that stands on its short side: 700 by 1000. One row does not fit.
    static let narrow = screen(34, CGRect(x: 0, y: 0, width: 700, height: 1000), dock: 70)

    /// A screen with a menu bar of 25 points at its top and a Dock at its bottom.
    static func screen(_ id: CGDirectDisplayID, _ frame: CGRect, dock: CGFloat, scale: CGFloat = 2) -> OverlayScreen {
        OverlayScreen(
            display: DrawDisplay(id: id, size: frame.size),
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY + dock, width: frame.width, height: frame.height - dock - 25),
            scale: scale
        )
    }
}

extension DrawControllerTests.Stage {
    /// A stage with the given screens. The pointer is in the middle of the first screen.
    convenience init(screens: [OverlayScreen]) {
        self.init()
        desk.screens = screens
        desk.pointer = CGPoint(x: screens[0].frame.midX, y: screens[0].frame.midY)
    }

    var panel: ToolbarPanel {
        get throws { try #require(controller.toolbarPanel) }
    }

    var toolbar: Toolbar {
        get throws { try panel.toolbarView }
    }

    /// The form and the frame of the toolbar now.
    var formAndFrame: [String] {
        get throws { [try toolbar.form.rawValue, "\(try panel.frame)"] }
    }

    /// The middle of the grip, counted from the top-left of the toolbar.
    var grip: CGPoint {
        get throws { CGPoint(x: try toolbar.layout.grip.midX, y: try toolbar.layout.grip.midY) }
    }

    /// The middle of the gap after a group of buttons, counted from the top-left of the toolbar.
    func gap(after group: Int) throws -> CGPoint {
        let frames = try toolbar.layout.frames
        let before = try #require(frames[group].last), after = try #require(frames[group + 1].first)
        return CGPoint(x: ((before.maxX + after.minX) / 2).rounded(.down), y: ((before.maxY + after.minY) / 2).rounded(.down))
    }

    private func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
        // The toolbar asks the desk for the pointer. It does not read the place of the event.
        try #require(NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    /// The mouse goes down on a point of the toolbar, counted from its top-left. Nothing moves
    /// the real pointer: the test sets the pointer of the desk and gives the event to the view.
    func grab(at point: CGPoint) throws {
        let frame = try panel.frame
        desk.pointer = CGPoint(x: frame.minX + point.x, y: frame.maxY - point.y)
        try toolbar.mouseDown(with: mouse(.leftMouseDown))
    }

    /// The pointer moves to a global point while the mouse is down.
    func move(to pointer: CGPoint) throws {
        desk.pointer = pointer
        try toolbar.mouseDragged(with: mouse(.leftMouseDragged))
    }

    func release() throws {
        try toolbar.mouseUp(with: mouse(.leftMouseUp))
    }

    /// A full drag of the toolbar: down on a point of the toolbar, a move of the pointer, and the release.
    func drag(from point: CGPoint, to pointer: CGPoint) throws {
        try grab(at: point)
        try move(to: pointer)
        try release()
    }

    /// The pointer rests on a button until its tip shows. No test waits: the test fires the timer.
    func rest(on name: String) throws {
        let button = try toolbar.button(named: name)
        try toolbar.pointerMoved(to: CGPoint(x: button.frame.midX, y: button.frame.midY))
        try #require(toolbar.tipTimer).fire()
    }

    /// The text of the tip that shows now. `nil` when no tip shows.
    var tip: String? {
        (controller.tipPanel?.contentView as? ToolbarTipView)?.text.string
    }
}

/// The forms of the toolbar, its place and its tips (D16, YAZ-2830), out of sight: rows 2.100 to 2.113.
///
/// The layout is tested as a pure function with the sizes of six and of nine tool buttons. The
/// place is tested through `DrawController` with fixed screens and a pointer that the test sets.
/// No test shows a window, moves the mouse or waits for a timer.
@MainActor @Suite struct ToolbarFormTests {
    typealias Stage = DrawControllerTests.Stage

    /// The sizes of the buttons of a toolbar with `tools` tool buttons, group by group: "Click
    /// through", the tools, Undo Redo Clear all, three sizes, six colours, Fade Hold Sticky, the gear and Close.
    static func groups(tools: Int) -> [[CGSize]] {
        func buttons(_ count: Int) -> [CGSize] { Array(repeating: CGSize(width: 28, height: 28), count: count) }
        let names = [40, 40, 48].map { CGSize(width: $0, height: 28) }
        return [buttons(1), buttons(tools), buttons(3), buttons(3), buttons(6), names, buttons(2)]
    }

    /// Nine tool buttons for a toolbar view, with no change of `Tool`: the tools of the app, and
    /// then the first ones again.
    static let nineTools = Array((Tool.allCases + Tool.allCases + Tool.allCases).prefix(9))

    static func size(tools: Int) -> (ToolbarForm) -> CGSize {
        { ToolbarLayout(form: $0, groups: groups(tools: tools)).size }
    }

    /// Nothing overlaps and nothing is cut: each button has its size, is inside the toolbar with
    /// the padding, and touches no other button and not the grip.
    static func expectClean(_ layout: ToolbarLayout, _ groups: [[CGSize]], _ note: Comment) {
        let frames = layout.frames.flatMap { $0 }
        let inside = CGRect(origin: .zero, size: layout.size).insetBy(dx: 4, dy: 4)
        #expect(layout.frames.map { $0.map { $0.size } } == groups, note)
        #expect(inside.contains(layout.grip) && layout.grip.width >= 10 && layout.grip.height >= 10, note)
        for (index, frame) in frames.enumerated() {
            #expect(inside.contains(frame), note)
            #expect(!frame.intersects(layout.grip), note)
            #expect(frame.origin.x == frame.origin.x.rounded() && frame.origin.y == frame.origin.y.rounded(), note)
            #expect(frames.dropFirst(index + 1).allSatisfy { !$0.intersects(frame) }, note)
        }
    }

    /// The names of the buttons in the order of rows 2.100 and 4.30, for the tools that the app has.
    static var approvedOrder: [String] {
        ["Click through"] + Tool.allCases.map { $0.name } + ["Undo", "Redo", "Clear all"]
            + MarkSize.allCases.map { $0.name } + MarkColor.allCases.map { $0.name } + StayMode.allCases.map { $0.name }
            + ["Settings", "Close"]
    }

    // MARK: The layout

    @Test func row2_100_theToolbarIsOneRowInTheApprovedOrder() throws {
        let toolbar = Toolbar(session: Fixture().session)
        #expect(toolbar.form == .row)
        let buttons = toolbar.subviews.compactMap { $0 as? ToolbarButton }
        #expect(buttons.map { $0.name } == ToolbarFormTests.approvedOrder)
        #expect(buttons.suffix(8).map { $0.name } == ["Blue", "Black", "White", "Fade", "Hold", "Sticky", "Settings", "Close"])

        // One row: each button has the same top, and each button is at the right of the button before it.
        #expect(Set(buttons.map { $0.frame.minY }) == [4])
        #expect(toolbar.frame.height == 36)
        for (left, right) in zip(buttons, buttons.dropFirst()) {
            #expect(left.frame.maxX < right.frame.minX, "\(left.name) is before \(right.name)")
        }
        for button in buttons {
            #expect(toolbar.bounds.contains(button.frame), "the button \(button.name)")
            #expect(button.accessibilityLabel() == button.name)
        }
        // The grip is at the start. Close is the last button, at the right end.
        #expect(toolbar.layout.grip.maxX < buttons[0].frame.minX)
        #expect(buttons.last?.frame.maxX == toolbar.bounds.maxX - 4)

        // The gap between two groups is wider than the room between two buttons of a group.
        let frames = toolbar.layout.frames
        #expect(frames.count == 7)
        for (group, next) in zip(frames, frames.dropFirst()) {
            #expect(try #require(next.first).minX - #require(group.last).maxX == 9)
            #expect(zip(group, group.dropFirst()).allSatisfy { $1.minX - $0.maxX == 2 })
        }
    }

    @Test func row2_100_theSizeOfTheRowWithSixAndWithNineTools() {
        for (tools, width) in [(6, 831), (9, 921)] {
            let groups = ToolbarFormTests.groups(tools: tools)
            let row = ToolbarLayout(form: .row, groups: groups)
            #expect(row.size == CGSize(width: width, height: 36))
            ToolbarFormTests.expectClean(row, groups, "the row with \(tools) tools")
            #expect(row.grip == CGRect(x: 4, y: 4, width: 10, height: 28))
            #expect(row.frames[0][0].origin == CGPoint(x: 23, y: 4))
        }
        // The toolbar of the app: the padding, the grip, each button, 2 points between two buttons
        // of a group, and 9 points before each of the seven groups. The names of the switch have
        // the width that the font of this Mac gives them.
        let toolbar = Toolbar(session: Fixture().session)
        let widths = toolbar.subviews.compactMap { $0 as? ToolbarButton }.map { $0.frame.width }
        #expect(widths.filter { $0 == 28 }.count == widths.count - 3)
        let betweenButtons = 2 * CGFloat(widths.count - 7)
        let width: CGFloat = 4 + 10 + 7 * 9 + widths.reduce(0, +) + betweenButtons + 4
        #expect(toolbar.frame.size == CGSize(width: width, height: 36))
    }

    /// YAZ-2830, completion: the layout takes its buttons from lists, and a new tool needs no change.
    @Test func theLayoutWorksWithNineToolsAndWithAnyNumberOfTools() {
        let sizes: [(ToolbarForm, CGSize, CGSize)] = [
            (.row, CGSize(width: 831, height: 36), CGSize(width: 921, height: 36)),
            (.twoRows, CGSize(width: 436, height: 72), CGSize(width: 510, height: 72)),
            (.column, CGSize(width: 56, height: 787), CGSize(width: 56, height: 877)),
            (.twoColumns, CGSize(width: 92, height: 436), CGSize(width: 92, height: 466)),
        ]
        for (form, six, nine) in sizes {
            #expect(ToolbarFormTests.size(tools: 6)(form) == six, "\(form) with six tools")
            #expect(ToolbarFormTests.size(tools: 9)(form) == nine, "\(form) with nine tools")
        }
        for form in ToolbarForm.allCases {
            for tools in 1...14 {
                let groups = ToolbarFormTests.groups(tools: tools)
                let layout = ToolbarLayout(form: form, groups: groups)
                ToolbarFormTests.expectClean(layout, groups, "\(form) with \(tools) tools")
                // The buttons keep their order: along a line, and from the first line to the second.
                let frames = layout.frames.flatMap { $0 }
                for (first, second) in zip(frames, frames.dropFirst()) {
                    // The next button is later in the same line, or it is in the next line.
                    let isNext = form.isVertical
                        ? first.maxY <= second.minY || first.maxX <= second.minX
                        : first.maxX <= second.minX || first.maxY <= second.minY
                    #expect(isNext, "\(form) with \(tools) tools")
                }
                // One more tool makes one line 30 points longer, or it changes nothing in the other direction.
                let more = ToolbarLayout(form: form, groups: ToolbarFormTests.groups(tools: tools + 1)).size
                if form.lineCount == 1 {
                    #expect(form.isVertical ? more == CGSize(width: layout.size.width, height: layout.size.height + 30)
                        : more == CGSize(width: layout.size.width + 30, height: layout.size.height))
                }
            }
        }

        // The toolbar view with nine tool buttons, in each form.
        let toolbar = Toolbar(session: Fixture().session, tools: ToolbarFormTests.nineTools)
        for form in ToolbarForm.allCases {
            toolbar.form = form
            let buttons = toolbar.subviews.compactMap { $0 as? ToolbarButton }
            #expect(buttons.count == 27)
            #expect(toolbar.frame.size == toolbar.layout.size)
            #expect(buttons.map { $0.frame } == toolbar.layout.frames.flatMap { $0 })
            for button in buttons {
                #expect(toolbar.bounds.contains(button.frame) && button.bounds.contains(button.keyFrame), "\(form), \(button.name)")
            }
        }
    }

    @Test func row2_101_aRowThatIsWiderThanTheVisiblePartIsTwoRows() throws {
        // The pure rule: the row of 831 points fits in 831 points, and not in 830 points.
        let size = ToolbarFormTests.size(tools: 6)
        #expect(ToolbarForm.fitting(vertical: false, in: CGRect(x: 0, y: 0, width: 831, height: 600), size: size) == .row)
        #expect(ToolbarForm.fitting(vertical: false, in: CGRect(x: 0, y: 0, width: 830, height: 600), size: size) == .twoRows)

        // Two rows: the groups keep their order, and the grip is as high as the two rows.
        let groups = ToolbarFormTests.groups(tools: 6)
        let layout = ToolbarLayout(form: .twoRows, groups: groups)
        ToolbarFormTests.expectClean(layout, groups, "two rows")
        #expect(layout.frames.map { $0[0].minY } == [4, 4, 4, 4, 40, 40, 40])
        #expect(layout.grip == CGRect(x: 4, y: 4, width: 10, height: 64))
        // The two rows are about as long: 409 and 386 points.
        #expect(layout.frames[3].last?.maxX == 23 + 409 && layout.frames[6].last?.maxX == 23 + 386)

        // On a screen of 700 points, drawing starts with two rows at the bottom centre.
        let stage = Stage(screens: [Desks.narrow])
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .twoRows)
        #expect(Desks.narrow.visibleFrame.contains(try stage.panel.frame))
        #expect(try stage.panel.frame.minY == Desks.narrow.visibleFrame.minY + 24)
        #expect(try abs(stage.panel.frame.midX - 350) <= 0.5)
        // The buttons of the view are in two rows too.
        #expect(Set(try stage.toolbar.subviews.compactMap { $0 as? ToolbarButton }.map { $0.frame.minY }) == [4, 40])
    }

    // MARK: The drop

    @Test func row2_102_aDropNearTheLeftOrTheRightEdgeMakesOneColumn() throws {
        let visible = Desks.main.visibleFrame
        let size = ToolbarFormTests.size(tools: 6)
        /// The drop of a row with its middle at `x`. The pointer is at the middle of the row.
        func drop(middle x: CGFloat) -> (form: ToolbarForm, frame: CGRect) {
            ToolbarLayout.drop(
                CGRect(x: x - 415.5, y: 500, width: 831, height: 36), pointer: CGPoint(x: x, y: 518), on: visible, size: size
            )
        }
        // "Near" is less than 120 points from the edge.
        #expect(drop(middle: 119).form == .column && drop(middle: 120).form == .row)
        #expect(drop(middle: 1920 - 119).form == .column && drop(middle: 1920 - 120).form == .row)
        #expect(drop(middle: 960).form == .row)
        // Past the edge is near too.
        #expect(drop(middle: -300).form == .column && drop(middle: 2100).form == .column)
        // The column is at that edge, 8 points from it, and it is fully in the visible part.
        #expect(drop(middle: 119).frame == CGRect(x: 8, y: 70, width: 56, height: 787))
        #expect(drop(middle: 100).frame.minX == 8 && drop(middle: 1900).frame.maxX == 1920 - 8)
        #expect(visible.contains(drop(middle: 100).frame) && visible.contains(drop(middle: 1900).frame))

        // The grip is at the start of the row. A drag of the grip to the edge makes a column
        // too: the pointer is near the edge, and the middle of the row is not.
        let atTheLeft = CGRect(x: 0, y: 500, width: 831, height: 36)
        #expect(ToolbarLayout.drop(atTheLeft, pointer: CGPoint(x: 9, y: 518), on: visible, size: size).form == .column)
        #expect(ToolbarLayout.drop(atTheLeft, pointer: CGPoint(x: 119, y: 518), on: visible, size: size).form == .column)
        #expect(ToolbarLayout.drop(atTheLeft, pointer: CGPoint(x: 120, y: 518), on: visible, size: size).form == .row)

        // Through the controller: the user takes the row at a gap and drops it at the left edge.
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row)
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 600))
        #expect(try stage.toolbar.form == .column)
        #expect(try stage.panel.frame.minX == 8)
        #expect(try stage.panel.frame.size == stage.toolbar.layout.size && stage.panel.frame.width < 80)
        #expect(visible.contains(try stage.panel.frame))
        // The buttons are one below the other.
        let buttons = try stage.toolbar.subviews.compactMap { $0 as? ToolbarButton }
        #expect(buttons.map { $0.name } == ToolbarFormTests.approvedOrder)
        #expect(zip(buttons, buttons.dropFirst()).allSatisfy { $0.frame.maxY < $1.frame.minY })

        // And at the right edge.
        try stage.drag(from: stage.grip, to: CGPoint(x: 1900, y: 900))
        #expect(try stage.toolbar.form == .column)
        #expect(try stage.panel.frame.maxX == 1920 - 8)
        #expect(visible.contains(try stage.panel.frame))
    }

    @Test func row2_103_aColumnThatIsHigherThanTheVisiblePartIsTwoColumns() throws {
        // The pure rule: the column of 787 points fits in 787 points, and not in 786 points.
        let size = ToolbarFormTests.size(tools: 6)
        #expect(ToolbarForm.fitting(vertical: true, in: CGRect(x: 0, y: 0, width: 900, height: 787), size: size) == .column)
        #expect(ToolbarForm.fitting(vertical: true, in: CGRect(x: 0, y: 0, width: 900, height: 786), size: size) == .twoColumns)

        let groups = ToolbarFormTests.groups(tools: 6)
        let layout = ToolbarLayout(form: .twoColumns, groups: groups)
        ToolbarFormTests.expectClean(layout, groups, "two columns")
        // The first column has "Click through", the tools, Undo Redo Clear all and the sizes. The
        // grip is above the two columns.
        #expect(layout.frames.map { $0[0].minX } == [4, 4, 4, 4, 50, 44, 50])
        #expect(layout.grip == CGRect(x: 4, y: 4, width: 84, height: 10))

        // The small screen: its visible part is 705 points high. A drop at the edge makes two columns.
        let stage = Stage(screens: [Desks.small])
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row)
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 40, y: 400))
        #expect(try stage.toolbar.form == .twoColumns)
        #expect(try stage.panel.frame.minX == 8)
        #expect(Desks.small.visibleFrame.contains(try stage.panel.frame))
        try stage.drag(from: stage.grip, to: CGPoint(x: 1270, y: 400))
        #expect(try stage.toolbar.form == .twoColumns)
        #expect(try stage.panel.frame.maxX == 1280 - 8)
        #expect(Desks.small.visibleFrame.contains(try stage.panel.frame))
    }

    @Test func row2_104_aDropAwayFromTheEdgesMakesOneRowAgain() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 600))
        #expect(try stage.toolbar.form == .column)

        // The user takes the column at its grip and drops it in the middle of the screen.
        let grip = try stage.grip
        try stage.drag(from: grip, to: CGPoint(x: 700, y: 800))
        #expect(try stage.toolbar.form == .row)
        #expect(try stage.panel.frame.size == stage.toolbar.layout.size && stage.panel.frame.height == 36)
        // The row starts where the user released the column: its top-left corner did not move.
        #expect(try stage.panel.frame.minX == 700 - grip.x && stage.panel.frame.maxY == 800 + grip.y)
        #expect(Desks.main.visibleFrame.contains(try stage.panel.frame))

        // 120 points from the edge is not near: a row. 119 points is near: a column again.
        try stage.drag(from: stage.grip, to: CGPoint(x: 60, y: 600))
        let column = try stage.panel.frame
        try stage.drag(from: CGPoint(x: column.width / 2, y: 5), to: CGPoint(x: 120, y: 600))
        #expect(try stage.toolbar.form == .row)
        try stage.drag(from: stage.grip, to: CGPoint(x: 60, y: 600))
        try stage.drag(from: CGPoint(x: column.width / 2, y: 5), to: CGPoint(x: 119, y: 600))
        #expect(try stage.toolbar.form == .column)
    }

    @Test func row2_105_theFormChangesAtTheReleaseAndTheToolbarStaysOnItsScreen() throws {
        let stage = Stage(screens: [Desks.main])
        let visible = Desks.main.visibleFrame
        stage.controller.toggleDrawing()
        let start = try stage.panel.frame
        let gap = try stage.gap(after: 2)

        // During the drag the toolbar follows the pointer, and it is still a row, also at the edge.
        try stage.grab(at: gap)
        try stage.move(to: CGPoint(x: 300, y: 600))
        #expect(try stage.toolbar.form == .row && stage.panel.frame.size == start.size)
        try stage.move(to: CGPoint(x: 30, y: 600))
        #expect(try stage.toolbar.form == .row && stage.panel.frame.size == start.size)
        #expect(try stage.panel.frame.origin == CGPoint(x: 30 - gap.x, y: 600 - (start.height - gap.y)))
        // Here a part of the toolbar is not on the screen, and nothing is stored yet.
        #expect(!visible.contains(try stage.panel.frame))
        #expect(stage.store.values["toolbarPlace"] == nil)

        // The release: now it is a column, fully in the visible part.
        try stage.release()
        #expect(try stage.toolbar.form == .column)
        #expect(visible.contains(try stage.panel.frame))
        #expect(stage.store.values["toolbarPlace"] != nil)

        // A row that the user drops below the Dock, or past the top right corner, moves into the visible part.
        try stage.drag(from: stage.grip, to: CGPoint(x: 700, y: 20))
        #expect(try stage.toolbar.form == .row)
        #expect(try stage.panel.frame.minY == visible.minY && visible.contains(stage.panel.frame))
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 1700, y: 1079))
        #expect(try stage.toolbar.form == .row)
        #expect(try stage.panel.frame.maxY == visible.maxY && stage.panel.frame.maxX == visible.maxX)

        // The pure rule. A frame that is too large keeps its top-left corner in the visible part.
        #expect(ToolbarLayout.keep(CGRect(x: -50, y: 0, width: 100, height: 40), inside: visible) == CGRect(x: 0, y: 70, width: 100, height: 40))
        #expect(ToolbarLayout.keep(CGRect(x: 500, y: 500, width: 3000, height: 2000), inside: visible) == CGRect(x: 0, y: 1055 - 2000, width: 3000, height: 2000))
    }

    @Test func row2_105_aClickWithNoMoveLeavesTheToolbarAsItIs() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        // The user puts the row at the left edge of the screen. He takes it at a gap, so the
        // pointer and the middle of the row are far from the edge. Now the grip is near the edge.
        let gap = try stage.gap(after: 2)
        try stage.drag(from: gap, to: CGPoint(x: gap.x, y: 600))
        let before = try stage.formAndFrame
        let stored = try #require(DrawPrefs(defaults: stage.store).toolbarPlace)
        #expect(try before[0] == "row" && stage.panel.frame.minX == 0)
        try stage.grab(at: stage.grip)
        #expect(stage.desk.pointer.x < 120)
        try stage.release()
        // The mouse went down and up with a move back to the same place.
        try stage.grab(at: stage.grip)
        try stage.move(to: stage.desk.pointer)
        try stage.release()
        #expect(try stage.formAndFrame == before)
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace == stored)
        // A release with no mouse down before it does nothing.
        try stage.release()
        #expect(try stage.formAndFrame == before)
    }

    @Test func row2_106_aDragOfTheGripOrOfAGapMovesTheToolbarAndMakesNoMark() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        let toolbar = try stage.toolbar
        // The toolbar never has the keyboard, so the click that starts the drag is a first click.
        #expect(toolbar.acceptsFirstMouse(for: nil))

        // The grip and each gap between two groups belong to the toolbar. A button takes its own click.
        // The row is the same above and below its middle, so the point needs no change for the test.
        #expect(toolbar.hitTest(try stage.grip) === toolbar)
        for group in 0..<6 {
            #expect(toolbar.hitTest(try stage.gap(after: group)) === toolbar, "the gap after group \(group)")
        }
        let pen = try toolbar.button(named: "Pen")
        #expect(toolbar.hitTest(CGPoint(x: pen.frame.midX, y: pen.frame.midY)) === pen)

        // The grip shows: its six dots are lighter than the toolbar.
        let picture = try Snapshot(of: toolbar, scale: 2)
        let grip = toolbar.layout.grip
        var light = 0
        for y in Int(grip.minY * 2)..<Int(grip.maxY * 2) {
            for x in Int(grip.minX * 2)..<Int(grip.maxX * 2) where picture[x, y].red > 90 { light += 1 }
        }
        #expect(light >= 6 * 4, "the grip has \(light) light pixels")

        // A drag of the grip moves the toolbar by the way of the pointer.
        let start = try stage.panel.frame
        let overlays = stage.controller.overlays
        try stage.grab(at: stage.grip)
        let down = stage.desk.pointer
        try stage.move(to: CGPoint(x: down.x + 100, y: down.y + 250))
        #expect(try stage.panel.frame == start.offsetBy(dx: 100, dy: 250))
        try stage.release()
        #expect(try stage.panel.frame == start.offsetBy(dx: 100, dy: 250))
        // A drag of a gap does the same.
        try stage.grab(at: stage.gap(after: 0))
        let secondDown = stage.desk.pointer
        try stage.move(to: CGPoint(x: secondDown.x - 40, y: secondDown.y - 30))
        try stage.release()
        #expect(try stage.panel.frame == start.offsetBy(dx: 60, dy: 220))

        // No mark, no mark in progress, and the mode and the overlays did not change.
        #expect(stage.session.markCount == 0 && stage.session.draft(on: Desks.main.display.id) == nil)
        #expect(stage.controller.mode == .drawing && stage.modes == [.drawing])
        #expect(zip(stage.controller.overlays, overlays).allSatisfy { $0 === $1 })
    }

    // MARK: The place

    @Test func row2_107_theNextStartHasThePlaceAndTheFormThatTheUserGave() throws {
        let stage = Stage(screens: [Desks.main, Desks.side])
        stage.controller.toggleDrawing()
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 700))
        let column = try stage.formAndFrame
        #expect(column[0] == "column")
        // The app stores the screen, the place on that screen, and the form.
        let frame = try stage.panel.frame
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace == ToolbarPlace(displayID: 32, origin: frame.origin, form: .column))

        // The mode changes do not move it.
        stage.controller.toggleClickThrough()
        stage.controller.toggleClickThrough()
        #expect(try stage.formAndFrame == column)

        // The next start of drawing. The pointer is on the other screen now, and that changes nothing.
        stage.controller.toggleDrawing()
        stage.desk.pointer = CGPoint(x: 3000, y: 700)
        stage.controller.toggleDrawing()
        #expect(try stage.formAndFrame == column)

        // The next start of the app: a new controller reads the same settings.
        func nextStartOfTheApp() throws -> [String] {
            let next = DrawController(
                defaults: stage.store, now: { 0 }, screens: { [Desks.main, Desks.side] }, pointer: { CGPoint(x: 3000, y: 700) }
            )
            next.toggleDrawing()
            let panel = try #require(next.toolbarPanel)
            #expect(!panel.isVisible)
            return [panel.toolbarView.form.rawValue, "\(panel.frame)"]
        }
        #expect(try nextStartOfTheApp() == column)

        // A row on the second screen, at a place that is not the bottom centre.
        try stage.drag(from: stage.grip, to: CGPoint(x: 2600, y: 1200))
        let row = try stage.formAndFrame
        #expect(try row[0] == "row" && Desks.side.visibleFrame.contains(stage.panel.frame))
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace?.displayID == 33)
        #expect(try DrawPrefs(defaults: stage.store).toolbarPlace?.origin.x == stage.panel.frame.minX - 1920)
        stage.controller.toggleDrawing()
        stage.controller.toggleDrawing()
        #expect(try stage.formAndFrame == row)
        #expect(try nextStartOfTheApp() == row)
    }

    @Test func row2_108_aPlaceThatIsNotValidGivesTheBottomCentreAsOneRow() throws {
        let stage = Stage(screens: [Desks.main, Desks.side])
        stage.controller.toggleDrawing()
        let rowSize = try stage.panel.frame.size
        let bottomCentreOfMain = Toolbar.origin(for: rowSize, on: Desks.main.visibleFrame)
        // The user puts a column at the right edge of the second screen.
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 4470, y: 700))
        let column = try stage.formAndFrame
        #expect(try column[0] == "column" && Desks.side.visibleFrame.contains(stage.panel.frame))
        let stored = try #require(DrawPrefs(defaults: stage.store).toolbarPlace)
        stage.controller.toggleDrawing()

        // The second screen is gone: the bottom centre of the screen that has the pointer, as one row.
        stage.desk.screens = [Desks.main]
        stage.desk.pointer = CGPoint(x: 500, y: 500)
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row && stage.panel.frame.origin == bottomCentreOfMain)
        stage.controller.toggleDrawing()
        // The app keeps the stored place. With the screen back, the toolbar is there again.
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace == stored)
        stage.desk.screens = [Desks.main, Desks.side]
        stage.controller.toggleDrawing()
        #expect(try stage.formAndFrame == column)
        stage.controller.toggleDrawing()

        // The screen is there, but the toolbar is not fully in its visible part: that screen has a high Dock now.
        stage.desk.screens = [Desks.main, Desks.screen(33, Desks.side.frame, dock: 800)]
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row && stage.panel.frame.origin == bottomCentreOfMain)
        stage.controller.toggleDrawing()

        // A stored value that is broken is no place.
        let broken: [Any] = [
            "column",
            ["display": 32, "x": 8.0, "y": 100.0] as [String: Any],
            ["display": 32, "x": 8.0, "y": 100.0, "form": "circle"] as [String: Any],
            ["display": -1, "x": 8.0, "y": 100.0, "form": "column"] as [String: Any],
            ["display": 32, "x": "8", "y": 100.0, "form": "column"] as [String: Any],
        ]
        stage.desk.screens = [Desks.main]
        for value in broken {
            stage.store.set(value, forKey: "toolbarPlace")
            #expect(DrawPrefs(defaults: stage.store).toolbarPlace == nil, "\(value)")
            stage.controller.toggleDrawing()
            #expect(try stage.toolbar.form == .row && stage.panel.frame.origin == bottomCentreOfMain, "\(value)")
            stage.controller.toggleDrawing()
        }
        // The same value with each part correct is a place.
        stage.store.set(["display": 32, "x": 8.0, "y": 100.0, "form": "column"] as [String: Any], forKey: "toolbarPlace")
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .column && stage.panel.frame.origin == CGPoint(x: 8, y: 100))
    }

    @Test func row2_108_theToolbarLeavesAScreenThatGoesAwayWhileDrawingIsOn() throws {
        let stage = Stage(screens: [Desks.main, Desks.side])
        stage.controller.toggleDrawing()
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 4470, y: 700))
        #expect(try stage.toolbar.form == .column)
        let panel = try stage.panel
        try stage.rest(on: "Pen")
        #expect(stage.tip != nil)

        stage.desk.screens = [Desks.main]
        stage.desk.pointer = CGPoint(x: 500, y: 500)
        stage.controller.screensChanged()
        // The same toolbar, as one row at the bottom centre of the screen that is left. The tip is gone.
        #expect(try stage.panel === panel && stage.toolbar.form == .row)
        #expect(panel.frame.origin == Toolbar.origin(for: panel.frame.size, on: Desks.main.visibleFrame))
        #expect(stage.tip == nil)
    }

    @Test func row2_109_theFirstStartIsOneRowAtTheBottomCentreOfTheScreenThatHasThePointer() throws {
        let stage = Stage(screens: [Desks.main, Desks.side])
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace == nil)
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row)
        #expect(try abs(stage.panel.frame.midX - 960) <= 0.5 && stage.panel.frame.minY == 70 + 24)
        #expect(Desks.main.visibleFrame.contains(try stage.panel.frame))
        stage.controller.toggleDrawing()

        // With no drag, nothing is stored. The next start follows the pointer again.
        #expect(stage.store.values["toolbarPlace"] == nil)
        stage.desk.pointer = CGPoint(x: 3000, y: 700)
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.form == .row)
        #expect(try abs(stage.panel.frame.midX - (1920 + 1280)) <= 0.5 && stage.panel.frame.minY == 24)
    }

    @Test func row2_113_oneToolbarGoesToTheOtherScreenAndTheRulesUseThatScreen() throws {
        let stage = Stage(screens: [Desks.main, Desks.side])
        stage.controller.toggleDrawing()
        let panel = try stage.panel
        #expect(Desks.main.visibleFrame.contains(panel.frame))

        // A drop in the middle of the second screen: the same toolbar, a row on that screen.
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 3200, y: 700))
        #expect(try stage.panel === panel && stage.toolbar.form == .row)
        #expect(Desks.side.visibleFrame.contains(panel.frame))
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace?.displayID == 33)

        // Near the right edge of the second screen: a column at that edge.
        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 4450, y: 700))
        #expect(try stage.toolbar.form == .column && panel.frame.maxX == 4480 - 8)
        #expect(Desks.side.visibleFrame.contains(panel.frame))
        // The column fits on the second screen. It keeps the height of the drop.
        #expect(try panel.frame.height == stage.toolbar.layout.size.height)

        // The pointer is on the first screen, near its right edge: a column at the right edge of the first screen.
        try stage.drag(from: stage.grip, to: CGPoint(x: 1900, y: 700))
        #expect(try stage.toolbar.form == .column && panel.frame.maxX == 1920 - 8)
        #expect(Desks.main.visibleFrame.contains(panel.frame))
        #expect(DrawPrefs(defaults: stage.store).toolbarPlace?.displayID == 32)
        // The pointer is on the second screen, near its left edge: a column at the left edge of the second screen.
        try stage.drag(from: stage.grip, to: CGPoint(x: 1950, y: 700))
        #expect(try stage.toolbar.form == .column && panel.frame.minX == 1920 + 8)
        #expect(Desks.side.visibleFrame.contains(panel.frame))
        // One toolbar and one overlay for each screen, the whole time.
        #expect(stage.controller.overlays.count == 2 && stage.nothingIsOnAScreen)
    }

    // MARK: The tip

    @Test func row2_110_theTipShowsTheNameAndTheKeyAfterHalfASecond() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        let toolbar = try stage.toolbar
        let arrow = try toolbar.button(named: "Arrow").frame
        #expect(toolbar.tipTimer == nil && stage.tip == nil)

        // The pointer comes to the Arrow button: a timer of half a second, and no tip yet.
        toolbar.pointerMoved(to: CGPoint(x: arrow.midX, y: arrow.midY))
        let timer = try #require(toolbar.tipTimer)
        #expect(timer.timeInterval == 0 && abs(timer.fireDate.timeIntervalSinceNow - 0.5) < 0.4)
        #expect(Toolbar.tipDelay == 0.5 && stage.tip == nil)
        // A move on the same button does not start the time again.
        toolbar.pointerMoved(to: CGPoint(x: arrow.midX + 3, y: arrow.midY - 3))
        #expect(toolbar.tipTimer === timer)

        // The half second is over: the tip shows the name and the key. The timer is gone.
        timer.fire()
        #expect(stage.tip == "Arrow  A")
        #expect(toolbar.tipTimer == nil && !timer.isValid)
        // The tip is a window of its own, and no test puts it on a screen.
        #expect(stage.controller.tipPanel?.isVisible == false)

        // The pointer leaves the button, to a gap: the tip goes away.
        toolbar.pointerMoved(to: try stage.gap(after: 0))
        #expect(stage.tip == nil && toolbar.tipTimer == nil)

        // The pointer leaves the button before the half second is over: no tip.
        toolbar.pointerMoved(to: CGPoint(x: arrow.midX, y: arrow.midY))
        let short = try #require(toolbar.tipTimer)
        toolbar.pointerMoved(to: nil)
        #expect(!short.isValid && toolbar.tipTimer == nil && stage.tip == nil)

        // A click removes the tip. It does not come back while the pointer stays on that button.
        try stage.rest(on: "Highlight")
        #expect(stage.tip == "Highlight  H")
        try toolbar.press("Highlight")
        #expect(stage.tip == nil && toolbar.tipTimer == nil)
        let highlight = try toolbar.button(named: "Highlight").frame
        toolbar.pointerMoved(to: CGPoint(x: highlight.midX + 2, y: highlight.midY))
        #expect(stage.tip == nil && toolbar.tipTimer == nil)
        // After the pointer left the button, the tip shows again.
        toolbar.pointerMoved(to: nil)
        try stage.rest(on: "Highlight")
        #expect(stage.tip == "Highlight  H")

        // From one button to the next: the old tip goes away at once, and the new one waits.
        let rectangle = try toolbar.button(named: "Rectangle").frame
        toolbar.pointerMoved(to: CGPoint(x: rectangle.midX, y: rectangle.midY))
        #expect(stage.tip == nil && toolbar.tipTimer != nil)
        try #require(toolbar.tipTimer).fire()
        #expect(stage.tip == "Rectangle  R")

        // A mouse down on the grip, at the start of a drag, removes the tip too.
        try stage.grab(at: stage.grip)
        #expect(stage.tip == nil)
        try stage.release()

        // Each button has a tip: the fixed keys, the gear, and a key that the settings changed.
        // Close has no key, so its tip is its name only (row 4.40).
        var tips: [String] = []
        for name in ["Click through", "Undo", "Redo", "Clear all", "Thick", "Red", "Sticky", "Settings", "Close"] {
            toolbar.pointerMoved(to: nil)
            try stage.rest(on: name)
            tips.append(try #require(stage.tip))
        }
        #expect(tips == [
            "Click through  esc", "Undo  ⌘Z", "Redo  ⇧⌘Z", "Clear all  ⌫", "Thick  3", "Red  4", "Sticky  S", "Settings  ⌘,", "Close",
        ])
        stage.session.toolbarKeys.set("q", for: .tool(.arrow))
        toolbar.pointerMoved(to: nil)
        try stage.rest(on: "Arrow")
        #expect(stage.tip == "Arrow  Q")
    }

    @Test func row2_111_theTipDoesNotNeedTheActiveApp() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        let toolbar = try stage.toolbar
        // The toolbar sees the pointer while the app is not the active app, and it sees the pointer leave.
        let options = try #require(toolbar.trackingAreas.first).options
        #expect(options.contains([.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]))
        // The tooltip of macOS is not used: it can stay away while the app is not the active app.
        #expect(toolbar.subviews.allSatisfy { $0.toolTip == nil })

        try stage.rest(on: "Arrow")
        let tip = try #require(stage.controller.tipPanel)
        // The tip does not activate the app, it does not hide when the app is not active, and
        // it never takes the mouse or the keyboard.
        #expect(tip.styleMask.contains(.nonactivatingPanel) && !tip.styleMask.contains(.titled))
        #expect(!tip.hidesOnDeactivate && tip.ignoresMouseEvents && !tip.canBecomeKey && !tip.canBecomeMain)
        // It is on each Space and above the overlays, as the toolbar. A screen capture leaves it out.
        #expect(try tip.level == stage.panel.level)
        #expect(tip.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]))
        #expect(tip.sharingType == .none && !tip.isOpaque && tip.backgroundColor == .clear)

        // The tip in click-through, where the toolbar is dim: it still shows.
        stage.controller.toggleClickThrough()
        toolbar.pointerMoved(to: nil)
        try stage.rest(on: "Click through")
        #expect(stage.tip == "Click through  esc")
    }

    @Test func row2_112_theColumnShowsEachKeyAndTheTipIsAtTheSideThatHasRoom() throws {
        let stage = Stage(screens: [Desks.main])
        let visible = Desks.main.visibleFrame
        stage.controller.toggleDrawing()
        let toolbar = try stage.toolbar
        let buttons = toolbar.subviews.compactMap { $0 as? ToolbarButton }
        let sizesInTheRow = buttons.map { $0.frame.size }
        let keysInTheRow = buttons.map { $0.keyFrame }

        try stage.drag(from: stage.gap(after: 2), to: CGPoint(x: 60, y: 700))
        #expect(toolbar.form == .column)
        // Each button has the size that it has in the row. Thus its key is in the same corner,
        // and Fade, Hold and Sticky show their full names.
        #expect(buttons.map { $0.frame.size } == sizesInTheRow && buttons.map { $0.keyFrame } == keysInTheRow)
        // Each button shows a key, but Close (row 4.40).
        #expect(buttons.filter { $0.key.isEmpty }.map { $0.name } == ["Close"])
        for button in buttons {
            #expect(button.bounds.contains(button.keyFrame), "the key of \(button.name)")
            #expect(toolbar.bounds.insetBy(dx: 4, dy: 4).contains(button.frame), "the button \(button.name)")
        }
        for name in ["Fade", "Hold", "Sticky"] {
            let button = try toolbar.button(named: name)
            #expect(button.attributedTitle.string == name)
            #expect(button.frame.width >= ceil(button.attributedTitle.size().width) + 8, "the name \(name) has room")
        }
        // The column is as wide as the widest name, and each other button is in its middle.
        #expect(try toolbar.frame.width == toolbar.button(named: "Sticky").frame.width + 8)
        #expect(try abs(toolbar.button(named: "Pen").frame.midX - toolbar.bounds.midX) <= 0.5)

        // The column is at the left edge: the tip is at its right, at the height of the button.
        let panel = try stage.panel
        try stage.rest(on: "Sticky")
        var tip = try #require(stage.controller.tipPanel).frame
        let sticky = try toolbar.button(named: "Sticky").frame
        #expect(stage.tip == "Sticky  S")
        #expect(tip.minX == panel.frame.maxX + 6)
        #expect(abs(tip.midY - (panel.frame.maxY - sticky.midY)) <= 0.5)
        #expect(visible.contains(tip) && !tip.intersects(panel.frame))

        // The column is at the right edge: the tip is at its left.
        try stage.drag(from: stage.grip, to: CGPoint(x: 1900, y: 700))
        #expect(toolbar.form == .column)
        toolbar.pointerMoved(to: nil)
        try stage.rest(on: "Settings")
        tip = try #require(stage.controller.tipPanel).frame
        #expect(tip.maxX == panel.frame.minX - 6)
        #expect(visible.contains(tip) && !tip.intersects(panel.frame))

        // A row has its tip above the button, in the middle of the button.
        try stage.drag(from: stage.grip, to: CGPoint(x: 600, y: 600))
        #expect(toolbar.form == .row)
        toolbar.pointerMoved(to: nil)
        try stage.rest(on: "Arrow")
        tip = try #require(stage.controller.tipPanel).frame
        let arrow = try toolbar.button(named: "Arrow").frame
        #expect(tip.minY == panel.frame.maxY + 6)
        #expect(abs(tip.midX - (panel.frame.minX + arrow.midX)) <= 0.5)

        // The pure rule, where there is no room: a row at the top of the screen has its tip
        // below it, and a tip at the end of the toolbar stays in the visible part.
        let size = CGSize(width: 60, height: 22)
        let atTheTop = CGRect(x: 0, y: 1055 - 36, width: 794, height: 36)
        let first = CGRect(x: 4, y: 1055 - 32, width: 28, height: 28)
        #expect(ToolbarLayout.tipOrigin(size: size, button: first, toolbar: atTheTop, isVertical: false, on: visible)
            == CGPoint(x: 0, y: 1055 - 36 - 6 - 22))
        let atTheBottom = CGRect(x: 8, y: 70, width: 56, height: 750)
        let last = CGRect(x: 22, y: 74, width: 28, height: 28)
        #expect(ToolbarLayout.tipOrigin(size: size, button: last, toolbar: atTheBottom, isVertical: true, on: visible)
            == CGPoint(x: 8 + 56 + 6, y: 77))
        let lowest = CGRect(x: 22, y: 72, width: 28, height: 10)
        #expect(ToolbarLayout.tipOrigin(size: size, button: lowest, toolbar: atTheBottom, isVertical: true, on: visible).y == 70)
    }

    /// Row 4.14 for the parts of YAZ-2830: with the mode off, no tip, no timer of a tip and no
    /// window exists.
    @Test func row4_14_theTipAndItsTimerDoNotLiveWhileTheModeIsOff() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        // A tip that waits.
        var toolbar = try stage.toolbar
        let pen = try toolbar.button(named: "Pen").frame
        toolbar.pointerMoved(to: CGPoint(x: pen.midX, y: pen.midY))
        let timer = try #require(toolbar.tipTimer)
        stage.controller.toggleDrawing()
        #expect(!timer.isValid && toolbar.tipTimer == nil)
        #expect(stage.controller.tipPanel == nil && stage.controller.toolbarPanel == nil)

        // A tip that shows.
        stage.controller.toggleDrawing()
        toolbar = try stage.toolbar
        try stage.rest(on: "Pen")
        let tip = try #require(stage.controller.tipPanel)
        stage.session.stop()
        #expect(stage.controller.mode == .off)
        #expect(stage.controller.tipPanel == nil && !tip.isVisible && toolbar.tipTimer == nil)
        #expect(stage.controller.timer == nil && stage.controller.screenObserver == nil && stage.controller.keysObserver == nil)
    }
}
