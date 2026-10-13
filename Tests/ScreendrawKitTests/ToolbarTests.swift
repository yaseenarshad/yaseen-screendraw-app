import AppKit
@testable import ScreendrawKit
import Testing

/// The toolbar view, out of sight: the rows of YAZ-2790 that are about its buttons, and the
/// switch of YAZ-2791. A test sends the action of a button. It does not click.
@MainActor @Suite struct ToolbarTests {
    @MainActor final class Stage {
        let fixture = Fixture()
        let toolbar: Toolbar

        init() {
            toolbar = Toolbar(session: fixture.session)
            fixture.session.onChange = { [unowned self] in self.toolbar.refresh() }
        }

        var session: DrawSession { fixture.session }

        func button(_ name: String) throws -> ToolbarButton {
            try #require(toolbar.button(named: name) as? ToolbarButton)
        }

        func press(_ name: String) throws {
            let button = try button(name)
            #expect(button.isEnabled, "the button \(name) is not enabled")
            // The action goes through the app object. It is an accessory app: no Dock icon, no window.
            NSApplication.shared.setActivationPolicy(.accessory)
            #expect(button.sendAction(button.action, to: button.target))
        }

        /// The names of the buttons that show as selected.
        var selected: Set<String> {
            Set(toolbar.subviews.compactMap { $0 as? ToolbarButton }.filter { $0.isOn }.map { $0.name })
        }
    }

    @Test func theButtonsAreInTheApprovedOrderInTwoRows() throws {
        let stage = Stage()
        let firstRow = ["Pen", "Highlight", "Arrow", "Rectangle", "Ellipse", "Text", "Undo", "Redo", "Clear all", "Close"]
        // The switch is after the colours (YAZ-2791).
        let secondRow = ["Thin", "Medium", "Thick", "Red", "Amber", "Green", "Blue", "Black", "White", "Fade", "Hold", "Sticky"]
        let buttons = stage.toolbar.subviews.compactMap { $0 as? ToolbarButton }
        #expect(buttons.count == firstRow.count + secondRow.count)

        for row in [firstRow, secondRow] {
            let frames = try row.map { try stage.button($0).frame }
            #expect(Set(frames.map { $0.minY }).count == 1)
            for (left, right) in zip(frames, frames.dropFirst()) {
                #expect(left.maxX <= right.minX, "the buttons of a row do not overlap")
            }
        }
        // The toolbar is flipped: the row of the tools is above the row of the sizes.
        #expect(try stage.button("Pen").frame.minY < stage.button("Thin").frame.minY)
        // Each button is inside the toolbar.
        for button in buttons {
            #expect(stage.toolbar.bounds.contains(button.frame), "the button \(button.name)")
            #expect(button.accessibilityLabel() == button.name)
        }
        // Close is at the right end. The free area before it is where a drag moves the toolbar.
        let close = try stage.button("Close").frame
        #expect(close.maxX == stage.toolbar.bounds.maxX - 4)
        #expect(close.minX - (try stage.button("Clear all").frame.maxX) > 28)
    }

    @Test func row2_2_and3_1_theFirstStartShowsPenThickRedAndSticky() {
        let stage = Stage()
        #expect(stage.selected == ["Pen", "Thick", "Red", "Sticky"])
    }

    @Test func row2_3_and3_2_aLaterStartShowsTheLastValues() throws {
        let stage = Stage()
        try stage.press("Ellipse")
        try stage.press("Thin")
        try stage.press("White")
        try stage.press("Hold")

        let next = Toolbar(session: stage.fixture.nextStart())
        let selected = next.subviews.compactMap { $0 as? ToolbarButton }.filter { $0.isOn }.map { $0.name }
        #expect(Set(selected) == ["Ellipse", "Thin", "White", "Hold"])
    }

    @Test func eachToolSizeColourAndStayButtonSelectsItsValue() throws {
        let stage = Stage()
        for tool in Tool.allCases {
            try stage.press(tool.name)
            #expect(stage.session.tool == tool)
            #expect(try stage.button(tool.name).isOn)
        }
        for size in MarkSize.allCases {
            try stage.press(size.name)
            #expect(stage.session.style.size == size)
        }
        for color in MarkColor.allCases {
            try stage.press(color.name)
            #expect(stage.session.style.color == color)
        }
        for stay in StayMode.allCases {
            try stage.press(stay.name)
            #expect(stage.session.stay == stay)
        }
        // One button of each group shows as selected. A click on the selected tool keeps it selected.
        #expect(stage.selected == ["Text", "Thick", "White", "Sticky"])
        try stage.press("Text")
        #expect(stage.selected == ["Text", "Thick", "White", "Sticky"])
    }

    @Test func row2_11_and2_12_theUndoAndRedoButtons() throws {
        let stage = Stage()
        // With no step, the two buttons are not available.
        #expect(try !stage.button("Undo").isEnabled && !stage.button("Redo").isEnabled)

        stage.session.drawLine(row: 0)
        stage.session.drawLine(row: 1)
        #expect(try stage.button("Undo").isEnabled && !stage.button("Redo").isEnabled)

        try stage.press("Undo")
        #expect(stage.session.markCount == 1)
        #expect(try stage.button("Undo").isEnabled && stage.button("Redo").isEnabled)
        try stage.press("Redo")
        #expect(stage.session.markCount == 2)
        #expect(try !stage.button("Redo").isEnabled)

        try stage.press("Undo")
        try stage.press("Undo")
        #expect(stage.session.markCount == 0)
        #expect(try !stage.button("Undo").isEnabled && stage.button("Redo").isEnabled)
    }

    @Test func row2_14_theClearAllButton() throws {
        let stage = Stage()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.drawLine(on: Screens.right.id)
        try stage.press("Clear all")
        #expect(stage.session.markCount == 0)
        try stage.press("Undo")
        #expect(stage.session.markCount == 2)
    }

    @Test func row2_15_theCloseButtonIsTheSameAsTheDrawHotkey() throws {
        let stage = Stage()
        stage.session.drawLine()
        stage.session.setStay(.fade)
        stage.session.drawLine(row: 1)
        try stage.press("Close")
        #expect(stage.session.mode == .off)
        // The Sticky mark is kept, and the Fade mark is dropped (row 4.5).
        #expect(stage.session.allMarks.map { $0.stay } == [.sticky])
    }

    @Test func row3_7_theSwitchChangesTheNextMarkOnly() throws {
        let stage = Stage()
        stage.session.drawLine(row: 0)
        try stage.press("Fade")
        stage.session.drawLine(row: 1)
        try stage.press("Hold")
        stage.session.drawLine(row: 2)
        #expect(stage.session.allMarks.map { $0.stay } == [.sticky, .fade, .hold])
        #expect(stage.selected.contains("Hold") && !stage.selected.contains("Fade"))
    }

    @Test func theButtonsNeverTakeTheKeyboard() throws {
        let stage = Stage()
        for button in stage.toolbar.subviews.compactMap({ $0 as? ToolbarButton }) {
            #expect(button.refusesFirstResponder)
            #expect(button.acceptsFirstMouse(for: nil))
        }
    }
}
