import AppKit
import Carbon.HIToolbox
import SwiftUI
@testable import ScreendrawKit
import Testing

/// Esc pauses the pen, the "Click through" button, and the marks that hide (D20, YAZ-2837), out
/// of sight: rows 4.30 to 4.45. They replace rows 4.8, 4.10 and 4.22.
///
/// The drawing part is real, with fixed screens and a clock that the test sets. The tests of the
/// menu and of the settings use the real shell too. A test hands an `NSEvent` to the overlay view.
/// It presses no key, shows no window and moves no mouse.
@MainActor @Suite struct EscPausesTests {
    typealias Stage = DrawControllerTests.Stage
    /// The real shell with the real drawing part, on one screen.
    typealias Shell = SettingsGearTests.Stage

    private static let fourArrows = "arrow.up.and.down.and.arrow.left.and.right"

    /// A key-down event for the overlay view, as AppKit gives it to the view that has the keyboard.
    private func key(_ keyCode: Int) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(keyCode)
        ))
    }

    /// The overlay of the first screen gets a key. Only mode drawing has an overlay with the keyboard.
    private func press(_ keyCode: Int, on controller: DrawController) throws {
        let overlay = try #require(controller.overlays.first)
        #expect(overlay.canBecomeKey)
        overlay.overlayView.keyDown(with: try key(keyCode))
    }

    /// The pixels of a toolbar button with no key and with no "on" look: its picture alone.
    private func pixels(of button: ToolbarButton) throws -> [Pixel] {
        let key = button.key, wasOn = button.isOn
        button.key = ""
        button.isOn = false
        defer {
            button.key = key
            button.isOn = wasOn
        }
        let picture = try Snapshot(of: button, scale: 2)
        return (0..<picture.height).flatMap { y in (0..<picture.width).map { x in picture[x, y] } }
    }

    /// The pixels of a toolbar button that has the given symbol of the system as its picture.
    private func pixels(ofSymbol name: String) throws -> [Pixel] {
        let image = try #require(NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
        return try pixels(of: ToolbarButton(name: name, image: image) {})
    }

    // MARK: The button "Click through"

    @Test func row4_30_theToolbarHasTheButtonClickThroughAfterTheGripAndBeforeSelectWithTheKeyEsc() throws {
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        let toolbar = try stage.toolbar
        let button = try toolbar.button(named: "Click through")

        // Its name, and the pointer arrow of the system as its picture.
        #expect(button.accessibilityLabel() == "Click through")
        #expect(button.image?.accessibilityDescription == "Click through" && button.imagePosition == .imageOnly)
        #expect(try pixels(of: button) == pixels(ofSymbol: "cursorarrow"))
        #expect(try pixels(of: button) != pixels(ofSymbol: EscPausesTests.fourArrows))
        #expect(button.isEnabled && button.acceptsFirstMouse(for: nil) && button.refusesFirstResponder)

        // It shows the key esc in its bottom right corner, as each other button shows its key (row 2.32).
        #expect(button.key == "esc")
        #expect(button.bounds.contains(button.keyFrame) && button.keyFrame.minY > button.bounds.midY)
        #expect(button.bounds.maxX - button.keyFrame.maxX <= 3 && button.bounds.maxY - button.keyFrame.maxY <= 3)

        // In each form it is the first button after the grip, before Select, and a group of its
        // own: the gap of a group (9 points) is after it.
        for form in ToolbarForm.allCases {
            toolbar.form = form
            let names = toolbar.subviews.compactMap { $0 as? ToolbarButton }.map { $0.name }
            #expect(names.prefix(2) == ["Click through", "Select"], "\(form)")
            #expect(toolbar.layout.frames[0] == [button.frame], "\(form)")
            let grip = toolbar.layout.grip, select = try toolbar.button(named: "Select").frame
            if form.isVertical {
                #expect(button.frame.minY - grip.maxY == 9 && select.minY - button.frame.maxY == 9, "\(form)")
                #expect(abs(select.midX - button.frame.midX) <= 0.5, "\(form)")
            } else {
                #expect(button.frame.minX - grip.maxX == 9 && select.minX - button.frame.maxX == 9, "\(form)")
                #expect(select.minY == button.frame.minY, "\(form)")
            }
        }

        // The hover tip agrees with the key on the button.
        toolbar.form = .row
        try stage.rest(on: "Click through")
        #expect(stage.tip == "Click through  esc")
        // In mode drawing the button is not lit.
        #expect(!button.isOn)
    }

    @Test func row4_31_aClickOnClickThroughInModeDrawingPausesThePenAndTheMarksStayVisible() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()
        let button = try stage.toolbar.button(named: "Click through")
        #expect(!button.isOn)

        try stage.press("Click through")
        #expect(stage.controller.mode == .clickThrough && stage.modes == [.drawing, .clickThrough])
        // The marks stay visible, as with the click-through hotkey (row 4.1): the new overlays show
        // them, ignore the mouse and cannot take the keyboard.
        #expect(!stage.session.marksAreHidden && stage.session.markCount == 1)
        #expect(stage.controller.overlays.map { $0.overlayView.markLayers.count } == [1, 0])
        #expect(stage.controller.overlays.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey })
        #expect(try stage.panel.alphaValue == 0.5)

        // The button is lit while the mode is click-through, and only then: also after the hotkey
        // and after Esc.
        #expect(button.isOn)
        stage.controller.toggleClickThrough()
        #expect(stage.controller.mode == .drawing && !button.isOn)
        stage.controller.toggleClickThrough()
        #expect(button.isOn)
        stage.controller.toggleClickThrough()
        try press(kVK_Escape, on: stage.controller)
        #expect(stage.controller.mode == .clickThrough && button.isOn)
        // The selected tool keeps its own "on" look.
        #expect(try stage.toolbar.button(named: "Pen").isOn)
    }

    @Test func row4_32_aClickOnClickThroughInClickThroughGoesBackToDrawingAndHiddenMarksShowAgain() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine()
        let button = try stage.toolbar.button(named: "Click through")

        // Esc hid the mark.
        try press(kVK_Escape, on: stage.controller)
        #expect(stage.session.marksAreHidden && stage.controller.overlays.isEmpty && button.isOn)

        try stage.press("Click through")
        #expect(stage.controller.mode == .drawing && !button.isOn)
        #expect(stage.modes == [.drawing, .clickThrough, .drawing])
        // The mark shows again, and the overlays take the mouse and the keyboard again (row 4.3).
        #expect(!stage.session.marksAreHidden)
        #expect(stage.controller.overlays.map { $0.overlayView.markLayers.count } == [1, 0])
        #expect(stage.controller.overlays.allSatisfy { !$0.ignoresMouseEvents && $0.canBecomeKey })
        #expect(try stage.panel.alphaValue == 1)

        // From click-through with visible marks, the button goes back to drawing too.
        try stage.press("Click through")
        #expect(stage.controller.mode == .clickThrough && !stage.session.marksAreHidden)
        try stage.press("Click through")
        #expect(stage.controller.mode == .drawing && stage.session.tool == .pen)
        stage.session.drawLine(row: 1)
        #expect(stage.session.markCount == 2)
    }

    @Test func row4_33_theSelectToolHasTheFourArrowsAndKeepsItsNameAndItsKey() throws {
        let stage = ToolbarTests.Stage()
        let select = try stage.button("Select")
        #expect(Toolbar.symbolName(for: .select) == EscPausesTests.fourArrows)
        // The picture on the button is that symbol of the system, not the pointer arrow.
        #expect(try pixels(of: select) == pixels(ofSymbol: EscPausesTests.fourArrows))
        #expect(try pixels(of: select) != pixels(ofSymbol: "cursorarrow"))

        // The name and the key did not change (row 2.80).
        #expect(Tool.select.name == "Select" && select.name == "Select" && select.accessibilityLabel() == "Select")
        #expect(select.image?.accessibilityDescription == "Select")
        #expect(ToolbarAction.tool(.select).startKey == "v" && select.key == "V")
        stage.session.toolbarKey("v")
        #expect(stage.session.tool == .select && select.isOn)
    }

    // MARK: Esc

    @Test func row4_34_escInModeDrawingPausesThePenDeletesNoMarkAndHidesTheMarks() throws {
        let stage = Stage()
        stage.controller.toggleDrawing()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.setStay(.hold)
        stage.session.drawLine(on: Screens.right.id)
        let marks = stage.session.allMarks
        let panel = try stage.panel, overlays = stage.controller.overlays
        #expect(!DrawPrefs(defaults: stage.store).marksStayAfterEsc)

        try press(kVK_Escape, on: stage.controller)
        #expect(stage.controller.mode == .clickThrough && stage.modes == [.drawing, .clickThrough])
        // No mark is deleted, and the history stays.
        #expect(stage.session.allMarks == marks && stage.session.canUndo)
        // The marks are hidden: no overlay shows them. The toolbar stays, dim.
        #expect(stage.session.marksAreHidden)
        #expect(stage.controller.overlays.isEmpty && overlays.allSatisfy { !$0.isVisible })
        #expect(stage.controller.toolbarPanel === panel && panel.alphaValue == 0.5)
        #expect(stage.nothingIsOnAScreen)

        // Esc with no mark pauses the pen too. It makes no Undo step.
        let session = Fixture().session
        var changes = 0
        session.onChange = { changes += 1 }
        session.escape()
        #expect(session.mode == .clickThrough && session.marksAreHidden && !session.canUndo && changes == 1)

        // Esc during a drag: the mark in progress is finished first (row 4.11), and it is kept.
        session.toggleClickThrough()
        session.pointerDown(at: point(100, 100), on: Screens.left.id)
        session.pointerDragged(to: point(160, 140))
        session.escape()
        #expect(session.mode == .clickThrough && session.markCount == 1)
    }

    @Test func row4_35_escWithAnOpenTextOrASelectedMarkDoesTheSmallJobFirst() {
        // An open text: only the text is cancelled (row 4.7). The next Esc pauses the pen.
        var session = Fixture().session
        session.drawLine()
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Not wanted")
        session.escape()
        #expect(session.textEdit == nil && session.mode == .drawing)
        #expect(session.allMarks.map { $0.mark.tool } == [.pen])
        session.escape()
        #expect(session.mode == .clickThrough && session.marksAreHidden)
        #expect(session.allMarks.map { $0.mark.tool } == [.pen])

        // A selected mark: only the selection goes away (row 2.87). The next Esc pauses the pen.
        session = Fixture().session
        session.drawLine()
        session.selectTool(.select)
        session.click(at: point(70, 20))
        #expect(session.selectedID != nil)
        session.escape()
        #expect(session.selectedID == nil && session.mode == .drawing && session.markCount == 1)
        session.escape()
        #expect(session.mode == .clickThrough && session.markCount == 1)

        // A text that is open again: the field closes with the old text, then the selection goes
        // away, and then the pen is paused.
        session = Fixture().session
        session.selectTool(.text)
        session.click(at: point(200, 150))
        session.textChanged("Label")
        session.completeText()
        session.selectTool(.select)
        session.click(at: point(205, 150))
        session.doubleClick(at: point(205, 150), on: Screens.left.id)
        session.textChanged("Label, changed")
        #expect(session.textEdit != nil)
        session.escape()
        #expect(session.textEdit == nil && session.selectedID != nil && session.mode == .drawing)
        session.escape()
        #expect(session.selectedID == nil && session.mode == .drawing)
        session.escape()
        #expect(session.mode == .clickThrough && session.allMarks.map { $0.mark.text } == ["Label"])
    }

    @Test func row4_36_theSettingsHaveTheSwitchMarksStayVisibleAfterEscAndItIsOffAtTheStart() throws {
        let shell = Shell()
        let settings = shell.app.settings, controller = shell.controller
        // Off at the start, and nothing is stored before the user changes it.
        #expect(!settings.marksStayAfterEsc && shell.store.values["drawMarksStayAfterEsc"] == nil)

        // Off: Esc hides the marks (row 4.34).
        controller.toggleDrawing()
        shell.session.drawLine()
        try press(kVK_Escape, on: controller)
        #expect(controller.mode == .clickThrough && controller.overlays.isEmpty)

        // On. The value is next to the other values of the drawing part, in the same store.
        settings.setMarksStayAfterEsc(true)
        #expect(settings.marksStayAfterEsc && shell.store.values["drawMarksStayAfterEsc"] as? Bool == true)
        #expect(DrawPrefs(defaults: shell.store).marksStayAfterEsc)
        // The switch is for the next Esc. The marks that are hidden now stay hidden.
        #expect(controller.overlays.isEmpty)

        // The next Esc, with no restart: click-through, and the marks stay visible.
        controller.toggleClickThrough()
        try press(kVK_Escape, on: controller)
        #expect(controller.mode == .clickThrough && !shell.session.marksAreHidden && shell.session.markCount == 1)
        #expect(controller.overlays.count == 1 && controller.overlays[0].overlayView.markLayers.count == 1)
        #expect(controller.overlays[0].ignoresMouseEvents && !controller.overlays[0].canBecomeKey)

        // The value stays after a restart of the app.
        let next = SettingsModel(store: SettingsStore(defaults: shell.store), hotKeys: FakeHotKeyRegistrar(), loginItem: FakeLoginItem())
        #expect(next.marksStayAfterEsc)

        // Off again: the next Esc hides the marks again.
        settings.setMarksStayAfterEsc(false)
        #expect(shell.store.values["drawMarksStayAfterEsc"] as? Bool == false)
        controller.toggleClickThrough()
        try press(kVK_Escape, on: controller)
        #expect(shell.session.marksAreHidden && controller.overlays.isEmpty)

        // A stored value that is no switch value gives the start value: off.
        shell.store.set("yes", forKey: "drawMarksStayAfterEsc")
        #expect(!DrawPrefs(defaults: shell.store).marksStayAfterEsc)
        shell.store.set(false, forKey: "drawMarksStayAfterEsc")

        // The form: the switch is in the part "Marks". Its picture changes with its value. With the
        // new row, the form with no red line is lower than the 610 points where it starts to
        // scroll, so the window with its title bar stays below 640 points (row 5.27).
        func form() throws -> Snapshot {
            let view = NSHostingView(rootView: SettingsView(model: settings))
            view.appearance = NSAppearance(named: .aqua)
            view.frame = CGRect(origin: .zero, size: view.fittingSize)
            #expect(view.frame.width == 460 && view.frame.height < 610, "the form is \(view.frame.size)")
            return try Snapshot(of: view)
        }
        let off = try form()
        // One red line still fits with no scroll: the form is higher, and it is below 610 points.
        settings.setFadeSeconds("0")
        #expect(try form().height > off.height)
        settings.setFadeSeconds("2")
        settings.setMarksStayAfterEsc(true)
        let on = try form()
        #expect(off.width == on.width && off.height == on.height)
        var changed = 0
        for y in 0..<off.height {
            for x in 0..<off.width where off[x, y] != on[x, y] { changed += 1 }
        }
        #expect(changed > 50, "the switch changed \(changed) pixels of the form")
        try off.write("v030-settings.png")
        try on.write("v030-settings-on.png")
    }

    // MARK: Hidden marks

    @Test func row4_37_hiddenMarksKeepTheUndoHistoryAndShowAgainWhenTheModeIsDrawing() throws {
        // The three ways back to mode drawing: a click on a tool, the "Click through" button, and the hotkey.
        for way in ["a tool", "the button", "the hotkey"] {
            let stage = Stage()
            let controller = stage.controller, session = stage.session
            controller.toggleDrawing()
            session.drawLine(row: 0, on: Screens.left.id)
            session.drawLine(row: 1, on: Screens.right.id)
            session.drawLine(row: 2, on: Screens.left.id)
            session.undo()
            let marks = session.allMarks
            #expect(marks.count == 2 && session.canUndo && session.canRedo)

            try press(kVK_Escape, on: controller)
            // The app keeps the marks and the history. Nothing shows them.
            #expect(session.marksAreHidden && controller.overlays.isEmpty, "\(way)")
            #expect(session.allMarks == marks && session.canUndo && session.canRedo, "\(way)")

            switch way {
            case "a tool": try stage.press("Arrow")
            case "the button": try stage.press("Click through")
            default: controller.toggleClickThrough()
            }
            #expect(controller.mode == .drawing && !session.marksAreHidden, "\(way)")
            #expect(session.tool == (way == "a tool" ? .arrow : .pen), "\(way)")
            // The marks show again at the same places on the same screens.
            #expect(session.allMarks == marks, "\(way)")
            #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [1, 1], "\(way)")
            // Redo and Undo still know the steps from before Esc.
            session.redo()
            #expect(session.markCount == 3, "\(way)")
            session.undo()
            session.undo()
            #expect(session.allMarks == [marks[0]], "\(way)")
            #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [1, 0], "\(way)")
        }
    }

    @Test func row4_37_theClocksOfFadeAndHoldMarksContinueWhileTheMarksAreHidden() throws {
        let stage = Stage()
        let controller = stage.controller, session = stage.session
        controller.toggleDrawing()
        session.drawLine(row: 0)
        session.setStay(.fade)
        session.drawLine(row: 1)
        session.setStay(.hold)
        session.drawLine(row: 2)
        let sticky = session.allMarks[0], fade = session.allMarks[1], hold = session.allMarks[2]

        // Fade is 2 seconds: full for 1 second, then it fades for 1 second. 1.5 seconds pass while
        // the marks are hidden.
        try press(kVK_Escape, on: controller)
        #expect(controller.overlays.isEmpty && session.markCount == 3)
        stage.clock.time += 1.5
        controller.tick()
        controller.toggleClickThrough()
        var layers = controller.overlays[0].overlayView.markLayers
        #expect(layers[sticky.id]?.opacity == 1 && layers[fade.id]?.opacity == 0.5 && layers[hold.id]?.opacity == 1)

        // Hidden again. The Fade mark is gone at 2 seconds, with nobody who sees it.
        try press(kVK_Escape, on: controller)
        stage.clock.time += 0.5
        controller.tick()
        #expect(session.allMarks.map { $0.id } == [sticky.id, hold.id])
        // Hold is 5 seconds after the last drawing activity, then the marks fade for 1 second.
        stage.clock.time += 3.5
        controller.tick()
        controller.toggleClickThrough()
        layers = controller.overlays[0].overlayView.markLayers
        #expect(layers.count == 2 && layers[sticky.id]?.opacity == 1 && layers[hold.id]?.opacity == 0.5)

        try press(kVK_Escape, on: controller)
        stage.clock.time += 0.5
        controller.tick()
        #expect(session.allMarks.map { $0.id } == [sticky.id] && !session.hasTimedMarks)
        // A mark that its clock removed does not come back with Undo (row 3.10).
        controller.toggleClickThrough()
        session.undo()
        #expect(session.markCount == 0)
    }

    @Test func row4_38_theClickThroughHotkeyInModeDrawingKeepsTheMarksVisible() {
        let stage = Stage()
        let controller = stage.controller
        controller.toggleDrawing()
        stage.session.drawLine(on: Screens.left.id)
        stage.session.drawLine(on: Screens.right.id)
        // The setting "Marks stay visible after Esc" is off. It is for Esc only.
        #expect(!DrawPrefs(defaults: stage.store).marksStayAfterEsc)

        controller.toggleClickThrough()
        #expect(controller.mode == .clickThrough && !stage.session.marksAreHidden)
        #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [1, 1])
        #expect(controller.overlays.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey })
        #expect(controller.toolbarPanel?.alphaValue == 0.5)
    }

    @Test func row4_39_showToolbarInModeOffKeepsTheKeptMarksHiddenUntilTheModeIsDrawing() throws {
        let shell = Shell()
        let controller = shell.controller
        // The app keeps a Sticky mark from the last time.
        controller.toggleDrawing()
        shell.session.drawLine()
        controller.toggleDrawing()
        #expect(controller.mode == .off && shell.session.markCount == 1)

        for way in ["the menu row", "the hotkey"] {
            if way == "the menu row" {
                click(try #require(shell.app.statusMenu.menu.item(withTitle: "Show toolbar")))
            } else {
                // The setting of Esc does not apply here: the kept marks stay hidden with it on too.
                shell.app.settings.setMarksStayAfterEsc(true)
                shell.hotKeys.press(HotKeyKind.clickThrough.startValue)
            }
            // The toolbar shows with the pen paused. The kept mark is not on the screen.
            #expect(controller.mode == .clickThrough && shell.menuShowsClickThrough, "\(way)")
            #expect(controller.toolbarPanel?.alphaValue == 0.5, "\(way)")
            #expect(shell.session.marksAreHidden && controller.overlays.isEmpty, "\(way)")
            #expect(shell.session.markCount == 1 && controller.timer == nil, "\(way)")
            #expect(try #require(controller.toolbarPanel).toolbarView.button(named: "Click through").isOn, "\(way)")

            // The mode is drawing: the kept mark shows again (row 4.6).
            if way == "the menu row" {
                try #require(controller.toolbarPanel).toolbarView.press("Pen")
            } else {
                shell.hotKeys.press(HotKeyKind.clickThrough.startValue)
            }
            #expect(controller.mode == .drawing && !shell.session.marksAreHidden, "\(way)")
            #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [1], "\(way)")
            controller.toggleDrawing()
            #expect(controller.mode == .off && shell.session.markCount == 1, "\(way)")
        }
    }

    @Test func row4_40_theDrawHotkeyAndCloseTurnAllOffAndKeepTheStickyMarksAndCloseShowsNoKey() throws {
        for way in ["the hotkey", "Close"] {
            for isHidden in [false, true] {
                let note: Comment = "\(way), hidden marks: \(isHidden)"
                let stage = Stage()
                let controller = stage.controller, session = stage.session
                controller.toggleDrawing()
                session.drawLine(row: 0)
                session.setStay(.fade)
                session.drawLine(row: 1)
                if isHidden { try press(kVK_Escape, on: controller) } else { controller.toggleClickThrough() }
                #expect(controller.mode == .clickThrough && session.marksAreHidden == isHidden, note)

                if way == "Close" { try stage.press("Close") } else { controller.toggleDrawing() }
                #expect(controller.mode == .off && !session.marksAreHidden, note)
                #expect(controller.overlays.isEmpty && controller.toolbarPanel == nil, note)
                #expect(controller.timer == nil && controller.screenObserver == nil && controller.keysObserver == nil, note)
                // The app keeps the Sticky mark and drops the Fade mark (row 4.5).
                #expect(session.allMarks.map { $0.stay } == [.sticky], note)

                // The draw hotkey again: the Sticky mark shows (row 4.6).
                controller.toggleDrawing()
                #expect(controller.mode == .drawing && !session.marksAreHidden, note)
                #expect(controller.overlays.map { $0.overlayView.markLayers.count } == [1, 0], note)
            }
        }

        // Close shows no key, and its tip is its name only.
        let stage = Stage(screens: [Desks.main])
        stage.controller.toggleDrawing()
        let close = try stage.toolbar.button(named: "Close")
        #expect(close.key.isEmpty)
        // The button draws nothing in its corner: its picture is the picture of the symbol alone.
        #expect(try pixels(of: close) == pixels(ofSymbol: "xmark"))
        let shown = try Snapshot(of: close, scale: 2)
        #expect(try (0..<shown.height).flatMap { y in (0..<shown.width).map { x in shown[x, y] } } == pixels(ofSymbol: "xmark"))
        try stage.rest(on: "Close")
        #expect(stage.tip == "Close")
    }

    @Test func row4_41_deleteClearsAllOrTheSelectedMarkAndEscRemovesNoMark() throws {
        let stage = Stage()
        let controller = stage.controller, session = stage.session
        controller.toggleDrawing()
        session.drawLine(row: 0)
        session.drawLine(row: 1)
        session.drawLine(row: 2)
        let marks = session.allMarks

        // Delete with a selected mark removes that mark only (row 2.86).
        session.selectTool(.select)
        session.click(at: point(70, 30))
        #expect(session.selectedID == marks[1].id)
        try press(kVK_Delete, on: controller)
        #expect(session.allMarks == [marks[0], marks[2]] && controller.mode == .drawing)
        // Esc removes no mark. It pauses the pen.
        try press(kVK_Escape, on: controller)
        #expect(controller.mode == .clickThrough && session.allMarks == [marks[0], marks[2]])

        // Delete with no selection clears all the marks (row 2.20), and drawing stays on.
        controller.toggleClickThrough()
        try press(kVK_ForwardDelete, on: controller)
        #expect(session.markCount == 0 && controller.mode == .drawing)
        // Esc with no mark: nothing to delete, and nothing comes back.
        try press(kVK_Escape, on: controller)
        #expect(session.markCount == 0)
        // The two deletes are Undo steps. Esc made no step.
        controller.toggleClickThrough()
        session.undo()
        #expect(session.allMarks == [marks[0], marks[2]])
        session.undo()
        #expect(session.allMarks.map { $0.id } == marks.map { $0.id })
    }

    @Test func row4_42_theGearPausesThePenWithTheMarksVisibleAndOpensTheSettings() throws {
        let shell = Shell()
        let controller = shell.controller
        controller.toggleDrawing()
        shell.session.drawLine()

        // Mode drawing: click-through with the marks visible, and then the settings window (row 2.41).
        try shell.pressTheGear()
        #expect(controller.mode == .clickThrough && shell.opened == [.clickThrough])
        #expect(!shell.session.marksAreHidden)
        #expect(controller.overlays.count == 1 && controller.overlays[0].overlayView.markLayers.count == 1)
        #expect(controller.overlays[0].ignoresMouseEvents)

        // Click-through after Esc: the settings window opens, and nothing else changes (row 2.42).
        // The marks stay hidden.
        controller.toggleClickThrough()
        try press(kVK_Escape, on: controller)
        try shell.pressTheGear()
        #expect(controller.mode == .clickThrough && shell.opened == [.clickThrough, .clickThrough])
        #expect(shell.session.marksAreHidden && controller.overlays.isEmpty && shell.session.markCount == 1)
    }

    @Test func row4_43_clickThroughWithHiddenMarksHasNoOverlayWindowAndATimerOnlyForFadeOrHoldMarks() throws {
        let stage = Stage()
        let controller = stage.controller, session = stage.session
        controller.toggleDrawing()
        session.drawLine(on: Screens.left.id)
        session.drawLine(on: Screens.right.id)
        let overlays = controller.overlays, panel = try stage.panel

        try press(kVK_Escape, on: controller)
        // No overlay window. The windows of mode drawing are closed.
        #expect(controller.overlays.isEmpty && overlays.allSatisfy { !$0.isVisible })
        // The toolbar stays. It is dim, and it still takes clicks.
        #expect(controller.toolbarPanel === panel && panel.alphaValue == 0.5 && !panel.ignoresMouseEvents)
        // Only Sticky marks exist: no timer. The observers of the screens and of the settings stay.
        #expect(controller.timer == nil)
        #expect(controller.screenObserver != nil && controller.keysObserver != nil)

        // A change of the screens makes no overlay. The marks of the screen that is gone are dropped (row 1.11).
        stage.desk.screens = [Screens.leftScreen]
        controller.screensChanged()
        #expect(controller.overlays.isEmpty && session.markCount == 1)
        #expect(controller.mode == .clickThrough && session.marksAreHidden)

        // A Fade mark: the timer runs while the mark is hidden, and it stops when the clock removed the mark.
        try stage.press("Pen")
        #expect(controller.overlays.count == 1)
        try stage.press("Fade")
        session.drawLine(row: 1)
        let timer = try #require(controller.timer)
        try press(kVK_Escape, on: controller)
        #expect(controller.overlays.isEmpty && controller.timer === timer && timer.isValid)
        stage.clock.time += 2
        controller.tick()
        #expect(session.markCount == 1 && controller.timer == nil && !timer.isValid)

        // Mode off from here: no window, no timer and no observer (row 4.14).
        controller.toggleDrawing()
        #expect(controller.mode == .off && controller.overlays.isEmpty && controller.toolbarPanel == nil)
        #expect(controller.timer == nil && controller.screenObserver == nil && controller.keysObserver == nil)
        #expect(!panel.isVisible)
    }

    @Test func row4_44_theMenuRowClickThroughHasItsCheckMarkWithVisibleAndWithHiddenMarks() throws {
        let shell = Shell()
        let controller = shell.controller
        let row = try #require(shell.app.statusMenu.menu.item(withTitle: "Show toolbar"))
        #expect(row.state == .off)
        controller.toggleDrawing()
        shell.session.drawLine()
        #expect(row.title == "Click through" && row.state == .off)

        // Click-through with visible marks.
        controller.toggleClickThrough()
        #expect(!shell.session.marksAreHidden && row.title == "Click through" && row.state == .on)
        controller.toggleClickThrough()
        #expect(row.state == .off)

        // Click-through with hidden marks, after Esc.
        try press(kVK_Escape, on: controller)
        #expect(shell.session.marksAreHidden && row.title == "Click through" && row.state == .on)
        #expect(shell.app.statusMenu.symbolName == "pencil.tip.crop.circle.fill")
        // A click on the row goes back to drawing, as the hotkey does.
        click(row)
        #expect(controller.mode == .drawing && row.state == .off)

        // Click-through with hidden marks, after "Show toolbar" from mode off.
        controller.toggleDrawing()
        #expect(row.title == "Show toolbar" && row.state == .off)
        click(row)
        #expect(shell.session.marksAreHidden && row.title == "Click through" && row.state == .on)
    }

    @Test func row4_45_escInClickThroughDoesNothingInTheApp() throws {
        for isHidden in [false, true] {
            let note: Comment = "hidden marks: \(isHidden)"
            let stage = Stage()
            let controller = stage.controller, session = stage.session
            controller.toggleDrawing()
            session.drawLine()
            if isHidden { try press(kVK_Escape, on: controller) } else { controller.toggleClickThrough() }
            let modes = stage.modes, revision = session.marksRevision

            // No window of the app can take the keyboard, so Esc goes to the app below (row 4.9).
            #expect(controller.overlays.count == (isHidden ? 0 : 2), note)
            #expect(controller.overlays.allSatisfy { !$0.canBecomeKey }, note)
            #expect(try !stage.panel.canBecomeKey, note)
            // If an Esc still arrives, the session ignores it.
            session.escape()
            #expect(controller.mode == .clickThrough && session.marksAreHidden == isHidden, note)
            #expect(session.markCount == 1 && session.marksRevision == revision && stage.modes == modes, note)
        }
    }
}
