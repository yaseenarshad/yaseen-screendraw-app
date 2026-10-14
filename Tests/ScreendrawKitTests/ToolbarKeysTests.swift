import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ScreendrawKit

/// The keys of the toolbar (D11, YAZ-2807), out of sight: rows 2.30 to 2.39 and 5.20 to 5.27.
///
/// The stage has the real drawing part and the real settings model on one `MemoryDefaults`, as
/// the app has them on `UserDefaults.standard`. A test hands `NSEvent` objects to the overlay
/// view. It presses no key, shows no window and takes no real hotkey.
@MainActor @Suite struct ToolbarKeysTests {
    @MainActor final class Stage {
        let defaults: MemoryDefaults
        let hotKeys = FakeHotKeyRegistrar()
        let controller: DrawController
        let settings: SettingsModel

        /// Drawing is on for the two test screens, unless `isOn` is false.
        /// A stage on the `defaults` of an earlier stage is a later start of the app.
        init(defaults: MemoryDefaults = MemoryDefaults(), isOn: Bool = true) {
            self.defaults = defaults
            controller = DrawController(
                defaults: defaults,
                now: { 0 },
                screens: { [Screens.leftScreen, Screens.rightScreen] },
                pointer: { CGPoint(x: 400, y: 300) }
            )
            settings = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: FakeLoginItem())
            settings.registerHotKeys()
            if isOn { controller.toggleDrawing() }
        }

        var session: DrawSession { controller.session }

        var toolbar: Toolbar {
            get throws { try #require(controller.toolbarPanel).toolbarView }
        }

        /// The overlay of the left screen.
        var overlay: OverlayView {
            get throws { try #require(controller.overlays.first).overlayView }
        }

        /// A key-down event. `keyCode` is the position of the key, and `characters` is what the key types.
        func key(
            _ characters: String, keyCode: Int = kVK_ANSI_X, flags: NSEvent.ModifierFlags = [], isARepeat: Bool = false
        ) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isARepeat,
                keyCode: UInt16(keyCode)
            ))
        }

        /// The overlay gets a key, as AppKit gives it to the view that has the keyboard.
        func type(_ characters: String, keyCode: Int = kVK_ANSI_X, flags: NSEvent.ModifierFlags = [], isARepeat: Bool = false) throws {
            try overlay.keyDown(with: key(characters, keyCode: keyCode, flags: flags, isARepeat: isARepeat))
        }

        /// The settings window: a click on the key of the action, and then a key press.
        /// The window controller gives the model the position, the modifiers and the characters of the press.
        func record(
            _ characters: String?, for action: ToolbarAction, keyCode: Int = kVK_ANSI_X, modifiers: NSEvent.ModifierFlags = []
        ) -> Bool {
            settings.startRecordingToolbarKey(action)
            return settings.keyDown(HotKeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers), characters: characters)
        }

        /// The tool, the size, the colour and the stay value of the session, as the names of their buttons.
        var values: [String] {
            [session.tool.name, session.style.size.name, session.style.color.name, session.stay.name]
        }

        /// The names of the buttons that the toolbar shows as selected.
        var selected: Set<String> {
            get throws {
                Set(try toolbar.subviews.compactMap { $0 as? ToolbarButton }.filter { $0.isOn }.map { $0.name })
            }
        }

        /// The keys that the settings model shows, in the order of the 18 actions.
        var shownKeys: String {
            ToolbarAction.all.map { settings.toolbarKey($0) }.joined()
        }
    }

    /// The table of D11, in the order of the toolbar.
    static let startKeys = "wharot123456789fgs"
    static let bothHotKeys: [HotKeyKind: HotKeyCombo] = [
        .draw: HotKeyKind.draw.startValue, .clickThrough: HotKeyKind.clickThrough.startValue,
    ]

    // MARK: The keys on the overlay

    @Test func row2_30_aToolbarKeySelectsTheToolTheSizeTheColourOrTheStayValue() throws {
        let stage = Stage()
        #expect(stage.values == ["Pen", "Thick", "Red", "Sticky"])

        // Each key of the table of D11 does the same as a click on its button.
        let table: [(key: String, button: String)] = [
            ("w", "Pen"), ("h", "Highlight"), ("a", "Arrow"), ("r", "Rectangle"), ("o", "Ellipse"), ("t", "Text"),
            ("1", "Thin"), ("2", "Medium"), ("3", "Thick"),
            ("4", "Red"), ("5", "Amber"), ("6", "Green"), ("7", "Blue"), ("8", "Black"), ("9", "White"),
            ("f", "Fade"), ("g", "Hold"), ("s", "Sticky"),
        ]
        #expect(table.map { $0.button } == ToolbarAction.all.map { $0.name })
        for (key, button) in table {
            try stage.type(key)
            #expect(stage.values.contains(button), "the key \(key)")
            // The toolbar shows the new selection.
            #expect(try stage.toolbar.button(named: button).isOn, "the key \(key)")
        }
        #expect(stage.controller.mode == .drawing)

        // A key changes one group only, and the next mark has the new values.
        try stage.type("o")
        try stage.type("1")
        try stage.type("7")
        try stage.type("g")
        #expect(stage.values == ["Ellipse", "Thin", "Blue", "Hold"])
        #expect(try stage.selected == ["Ellipse", "Thin", "Blue", "Hold"])
        stage.session.drag([point(50, 50), point(150, 120)])
        let placed = try #require(stage.session.allMarks.last)
        #expect(placed.mark.tool == .ellipse && placed.mark.style == MarkStyle(color: .blue, size: .thin) && placed.stay == .hold)

        // The app remembers the values: a later start of the app has them.
        let next = DrawSession(prefs: DrawPrefs(defaults: stage.defaults), now: { 0 })
        #expect(next.tool == .ellipse && next.style == MarkStyle(color: .blue, size: .thin) && next.stay == .hold)

        // A key that is no toolbar key changes nothing.
        for key in ["x", "0", "z", " ", "\r", "\t"] { try stage.type(key) }
        #expect(stage.values == ["Ellipse", "Thin", "Blue", "Hold"])
        #expect(stage.controller.mode == .drawing && stage.session.markCount == 1)
    }

    @Test func row2_31_pAlsoSelectsThePenWhileNoActionHasP() throws {
        let stage = Stage()
        try stage.type("h")
        #expect(stage.session.tool == .highlight)
        try stage.type("p")
        #expect(stage.session.tool == .pen)
        #expect(try stage.selected.contains("Pen"))
        // W is still the key of the Pen, and the button shows W.
        try stage.type("a")
        try stage.type("w")
        #expect(stage.session.tool == .pen)
        #expect(try stage.toolbar.button(named: "Pen").key == "W")

        // The Pen gets a different key: P is still its second key.
        #expect(stage.record("x", for: .tool(.pen)))
        try stage.type("a")
        try stage.type("p")
        #expect(stage.session.tool == .pen)

        // Highlight gets P. The app accepts it, and P is the key of Highlight only.
        #expect(stage.record("p", for: .tool(.highlight)))
        #expect(stage.settings.toolbarKeyProblem == nil)
        #expect(stage.settings.toolbarKey(.tool(.highlight)) == "p")
        try stage.type("p")
        #expect(stage.session.tool == .highlight)
        try stage.type("x")
        #expect(stage.session.tool == .pen)
    }

    @Test func row2_32_eachButtonShowsItsKeyInItsBottomRightCorner() throws {
        let stage = Stage()
        let toolbar = try stage.toolbar
        let buttons = toolbar.subviews.compactMap { $0 as? ToolbarButton }
        let shown = Dictionary(uniqueKeysWithValues: buttons.map { ($0.name, $0.key) })
        #expect(shown == [
            "Pen": "W", "Highlight": "H", "Arrow": "A", "Rectangle": "R", "Ellipse": "O", "Text": "T",
            "Undo": "⌘Z", "Redo": "⇧⌘Z", "Clear all": "⌫", "Close": "esc",
            "Thin": "1", "Medium": "2", "Thick": "3",
            "Red": "4", "Amber": "5", "Green": "6", "Blue": "7", "Black": "8", "White": "9",
            "Fade": "F", "Hold": "G", "Sticky": "S",
            "Settings": "⌘,",
        ])

        // The key is small and grey. It is brighter on a selected button and weaker on a button that is not available.
        let pen = try toolbar.button(named: "Pen"), arrow = try toolbar.button(named: "Arrow"), undo = try toolbar.button(named: "Undo")
        func strength(_ button: ToolbarButton) -> CGFloat? {
            (button.keyText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.alphaComponent
        }
        #expect(arrow.keyText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NSFont.systemFont(ofSize: 8, weight: .semibold))
        #expect(pen.isOn && !arrow.isOn && !undo.isEnabled)
        #expect(try #require(strength(arrow)) > 0.5)
        #expect(try #require(strength(pen)) > #require(strength(arrow)))
        #expect(try #require(strength(undo)) < #require(strength(arrow)))

        // The picture of each button with and without its key. The pixels that differ are the key.
        let scale = 2
        for button in buttons {
            // AppKit fills the layer of the button with `draw(_:)`. That is where the key is drawn.
            #expect(!button.wantsUpdateLayer)
            // The corner: 3 points or less from the right edge and from the bottom edge. The button counts from its top.
            let frame = button.keyFrame
            #expect(button.bounds.contains(frame), "the key of \(button.name) is cut off")
            #expect(button.bounds.maxX - frame.maxX <= 3 && button.bounds.maxY - frame.maxY <= 3, "the button \(button.name)")
            #expect(frame.minY > button.bounds.midY, "the key of \(button.name) is in the bottom half")

            let key = button.key, wasOn = button.isOn
            // A selected button has a background below the picture. The test needs the picture alone.
            button.isOn = false
            button.key = ""
            let plain = try Snapshot(of: button, scale: CGFloat(scale))
            button.key = key
            let withKey = try Snapshot(of: button, scale: CGFloat(scale))
            button.isOn = wasOn

            var ink = 0, onThePicture = 0, outsideTheFrame = 0, atTheEdge = 0
            for y in 0..<plain.height {
                for x in 0..<plain.width where plain[x, y] != withKey[x, y] {
                    ink += 1
                    if plain[x, y].alpha > 0 { onThePicture += 1 }
                    if !frame.contains(CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(scale), y: (CGFloat(y) + 0.5) / CGFloat(scale))) {
                        outsideTheFrame += 1
                    }
                    if x == plain.width - 1 || y == plain.height - 1 { atTheEdge += 1 }
                }
            }
            // The key is there, it does not cover the picture or the name, and the edge of the button does not cut it.
            #expect(ink > 15, "the key of \(button.name) has \(ink) pixels")
            #expect(onThePicture == 0, "the key of \(button.name) covers \(onThePicture) pixels of the picture")
            #expect(outsideTheFrame == 0 && atTheEdge == 0, "the key of \(button.name)")
        }

        // The pictures for the review. At scale 2 the picture has the pixels of a Retina screen.
        try Snapshot(of: toolbar, scale: 2).write("toolbar-keys.png")
        try Snapshot(of: toolbar, scale: 1).write("toolbar-keys-1x.png")
        try Snapshot(of: toolbar, scale: 4).write("toolbar-keys-4x.png")
    }

    @Test func row2_33_aKeyWhileATextIsOpenIsForTheTyping() throws {
        let stage = Stage()
        try stage.type("t")
        #expect(stage.session.tool == .text)
        stage.session.click(at: point(100, 100))
        let window = try #require(stage.controller.overlays.first)
        let field = try #require(window.overlayView.textView)
        // The text field has the keyboard of the overlay window, so AppKit gives each key to the field.
        #expect(window.firstResponder === field)

        // The window gets the keys H, 4 and Shift-A. Each one is a toolbar key, and each one goes into the text.
        window.sendEvent(try stage.key("h", keyCode: kVK_ANSI_H))
        window.sendEvent(try stage.key("4", keyCode: kVK_ANSI_4))
        window.sendEvent(try stage.key("A", keyCode: kVK_ANSI_A, flags: .shift))
        #expect(field.string == "h4A")
        #expect(stage.session.textEdit?.text == "h4A")
        #expect(stage.values == ["Text", "Thick", "Red", "Sticky"])

        // A key that still gets to the session while the text is open changes nothing.
        stage.session.toolbarKey("h")
        stage.session.toolbarKey("4")
        #expect(stage.values == ["Text", "Thick", "Red", "Sticky"])
        #expect(stage.session.textEdit?.text == "h4A" && stage.session.markCount == 0)

        // Return finishes the text. Then the overlay view has the keyboard again, and H is a toolbar key.
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(window.firstResponder === window.overlayView)
        #expect(stage.session.allMarks.map { $0.mark.text } == ["h4A"])
        window.sendEvent(try stage.key("h", keyCode: kVK_ANSI_H))
        #expect(stage.session.tool == .highlight)
    }

    @Test func row2_34_inClickThroughAndInModeOffNoWindowGetsTheKey() throws {
        let stage = Stage()
        // The toolbar keys are no global hotkeys: macOS knows the two hotkeys of the app only.
        #expect(HotKeyKind.allCases == [.draw, .clickThrough])
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
        #expect(stage.record("x", for: .tool(.arrow)))
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)

        // Click-through: no overlay can take the keyboard, so a key goes to the app below.
        stage.controller.toggleClickThrough()
        #expect(stage.controller.mode == .clickThrough)
        #expect(stage.controller.overlays.count == 2)
        #expect(stage.controller.overlays.allSatisfy { !$0.canBecomeKey })
        // The toolbar never takes the keyboard.
        #expect(try #require(stage.controller.toolbarPanel).canBecomeKey == false)
        // The session does nothing with a key in this mode.
        stage.session.toolbarKey("h")
        #expect(stage.values == ["Pen", "Thick", "Red", "Sticky"] && stage.controller.mode == .clickThrough)

        // Mode off: no window exists, and nothing listens for a key or for a change of the settings.
        stage.controller.toggleDrawing()
        #expect(stage.controller.mode == .off)
        #expect(stage.controller.overlays.isEmpty && stage.controller.toolbarPanel == nil)
        #expect(stage.controller.keysObserver == nil && stage.controller.screenObserver == nil && stage.controller.timer == nil)
        stage.session.toolbarKey("h")
        #expect(stage.values == ["Pen", "Thick", "Red", "Sticky"] && stage.controller.mode == .off)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
    }

    @Test func row2_35_aKeyWithCommandControlOrOptionIsNotAToolbarKey() throws {
        let stage = Stage()
        let combinations: [NSEvent.ModifierFlags] = [
            .command, .control, .option, [.command, .shift], [.control, .option], [.command, .control, .option, .shift],
        ]
        for flags in combinations {
            for key in ["h", "4", "1", "f", "p"] { try stage.type(key, flags: flags) }
        }
        #expect(stage.values == ["Pen", "Thick", "Red", "Sticky"])
        #expect(ToolbarKeys.key(typed: "h", modifiers: .command) == nil)
        #expect(ToolbarKeys.key(typed: "h", modifiers: [.shift, .capsLock, .numericPad, .function]) == "h")

        // Command-Z and Shift-Command-Z do not change: Undo and Redo. Z is not a toolbar key.
        stage.session.drawLine()
        let overlay = try stage.overlay
        #expect(overlay.performKeyEquivalent(with: try stage.key("z", keyCode: kVK_ANSI_Z, flags: .command)))
        #expect(stage.session.markCount == 0)
        #expect(overlay.performKeyEquivalent(with: try stage.key("z", keyCode: kVK_ANSI_Z, flags: [.command, .shift])))
        #expect(stage.session.markCount == 1)
        // Also when Z is a toolbar key: Command-Z is Undo, and Z with no modifier is the toolbar key.
        #expect(stage.record("z", for: .tool(.arrow)))
        #expect(overlay.performKeyEquivalent(with: try stage.key("z", keyCode: kVK_ANSI_Z, flags: .command)))
        #expect(stage.session.markCount == 0 && stage.session.tool == .pen)
        try stage.type("z", keyCode: kVK_ANSI_Z)
        #expect(stage.session.tool == .arrow)
    }

    @Test func row2_36_shiftAndCapsLockDoNotStopAKey() throws {
        let stage = Stage()
        // With Shift or Caps Lock, the key types the capital letter.
        try stage.type("H", flags: .shift)
        #expect(stage.session.tool == .highlight)
        try stage.type("A", flags: .capsLock)
        #expect(stage.session.tool == .arrow)
        try stage.type("G", flags: [.shift, .capsLock])
        #expect(stage.session.stay == .hold)
        try stage.type("P", flags: .shift)
        #expect(stage.session.tool == .pen)
        // A digit with Caps Lock is the same digit.
        try stage.type("5", flags: .capsLock)
        #expect(stage.session.style.color == .amber)
    }

    @Test func row2_37_aKeyDuringADragDoesNothing() throws {
        let stage = Stage()
        stage.session.pointerDown(at: point(50, 50), on: Screens.left.id)
        stage.session.pointerDragged(to: point(150, 50))

        for key in ["r", "9", "1", "f", "p"] { try stage.type(key) }
        // The session and the toolbar keep the tool, the size, the colour and the stay value.
        #expect(stage.values == ["Pen", "Thick", "Red", "Sticky"])
        #expect(try stage.selected == ["Pen", "Thick", "Red", "Sticky"])
        // The drag is not finished by the key, and it continues.
        #expect(stage.session.markCount == 0)
        #expect(stage.session.draft(on: Screens.left.id)?.points == [point(50, 50), point(150, 50)])
        stage.session.pointerUp(at: point(250, 50))

        // The mark has the tool and the style of its start.
        let placed = try #require(stage.session.allMarks.last)
        #expect(stage.session.markCount == 1)
        #expect(placed.mark.tool == .pen && placed.mark.style == MarkStyle(color: .red, size: .thick) && placed.stay == .sticky)
        #expect(placed.mark.points == [point(50, 50), point(150, 50), point(250, 50)])

        // After the drag, the keys work again.
        try stage.type("r")
        try stage.type("9")
        #expect(stage.values == ["Rectangle", "Thick", "White", "Sticky"])
    }

    @Test func row2_38_aKeyThatStaysDownMakesOneChange() throws {
        let stage = Stage()
        var changes = 0
        let showChange = stage.session.onChange
        stage.session.onChange = {
            changes += 1
            showChange?()
        }

        // The first key-down makes the change. macOS then sends the key again while it is down.
        try stage.type("h")
        #expect(stage.session.tool == .highlight && changes == 1)
        for _ in 0..<20 { try stage.type("h", isARepeat: true) }
        #expect(changes == 1)

        // A key that is down from before does not change a value that the toolbar set after it.
        try stage.toolbar.press("Arrow")
        for _ in 0..<5 { try stage.type("h", isARepeat: true) }
        #expect(stage.session.tool == .arrow)
        // The key goes up and down again: one more change.
        try stage.type("h")
        #expect(stage.session.tool == .highlight)
    }

    @Test func row2_39_theCharacterCountsNotThePositionOfTheKey() throws {
        let stage = Stage()
        // A French keyboard: the key at the position of the US letter Q types "a".
        try stage.type("a", keyCode: kVK_ANSI_Q)
        #expect(stage.session.tool == .arrow)
        // The key at the position of the US letter A types "q" there. That is no toolbar key.
        try stage.type("w", keyCode: kVK_ANSI_Z)
        #expect(stage.session.tool == .pen)
        try stage.type("q", keyCode: kVK_ANSI_A)
        #expect(stage.session.tool == .pen)
        // The position of the US digit 4 types "'" with no Shift on that keyboard.
        try stage.type("'", keyCode: kVK_ANSI_4)
        #expect(stage.session.style.color == .red)
        try stage.type("7", keyCode: kVK_ANSI_7, flags: .shift)
        #expect(stage.session.style.color == .blue)

        // A letter of a different script can be a key. The recorder also takes the character, not the position.
        #expect(stage.record("Ф", for: .stay(.fade), keyCode: kVK_ANSI_A))
        #expect(stage.settings.toolbarKey(.stay(.fade)) == "ф")
        try stage.type("ф", keyCode: kVK_ANSI_A)
        #expect(stage.session.stay == .fade)
        #expect(stage.session.tool == .pen)
    }

    // MARK: Settings

    @Test func row5_20_theSettingsHaveTheToolbarKeysInFourGroups() throws {
        let stage = Stage(isOn: false)
        #expect(ToolbarAction.groups.map { $0.title } == ["Tools", "Sizes", "Colours", "Stay"])
        #expect(ToolbarAction.groups.map { $0.actions.map { $0.name } } == [
            ["Pen", "Highlight", "Arrow", "Rectangle", "Ellipse", "Text"],
            ["Thin", "Medium", "Thick"],
            ["Red", "Amber", "Green", "Blue", "Black", "White"],
            ["Fade", "Hold", "Sticky"],
        ])
        #expect(ToolbarAction.all.count == 18 && Set(ToolbarAction.all).count == 18)
        #expect(Set(ToolbarAction.all.map { $0.id }).count == 18)
        // Each action shows its key: the table of D11.
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)
        #expect(ToolbarAction.all.map { $0.startKey }.joined() == ToolbarKeysTests.startKeys)

        // Each action can be changed: its recorder starts, and a second click stops it.
        for action in ToolbarAction.all {
            stage.settings.startRecordingToolbarKey(action)
            #expect(stage.settings.recordingToolbarKey == action)
        }
        stage.settings.cancelRecording()
        #expect(stage.settings.recordingToolbarKey == nil)

        // The part "Toolbar keys" makes the form higher than the form of the two hotkeys was (163 points).
        let size = NSHostingView(rootView: SettingsView(model: stage.settings)).fittingSize
        #expect(size.width == 460 && size.height > 300)

        // The pictures for the review: the form, the form in dark mode, a recorder that listens, and a refusal.
        try picture(of: stage.settings).write("settings-keys.png")
        try picture(of: stage.settings, appearance: .darkAqua).write("settings-keys-dark.png")
        stage.settings.startRecordingToolbarKey(.color(.amber))
        try picture(of: stage.settings).write("settings-keys-recording.png")
        _ = stage.settings.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: []), characters: "w")
        try picture(of: stage.settings).write("settings-keys-refused.png")
    }

    /// The form of the settings window as a picture, with no window.
    private func picture(of model: SettingsModel, appearance: NSAppearance.Name = .aqua) throws -> Snapshot {
        let view = NSHostingView(rootView: SettingsView(model: model))
        view.appearance = NSAppearance(named: appearance)
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        return try Snapshot(of: view)
    }

    @Test func row5_21_aNewKeyIsOneLetterDigitOrPunctuationMark() {
        let stage = Stage(isOn: false)
        let pen = ToolbarAction.tool(.pen)

        // A letter, a digit and a punctuation mark are valid. The case of a letter does not count.
        for (typed, key) in [("x", "x"), ("X", "x"), ("0", "0"), (";", ";"), ("/", "/"), ("[", "["), ("=", "="), ("`", "`"), ("é", "é")] {
            #expect(stage.record(typed, for: pen) == true)
            #expect(stage.settings.recordingToolbarKey == nil)
            #expect(stage.settings.toolbarKey(pen) == key, "typed \(typed)")
            #expect(stage.settings.toolbarKeyProblem == nil)
        }
        // Shift is no problem: the key is what the press types.
        #expect(stage.record("!", for: pen, keyCode: kVK_ANSI_1, modifiers: .shift))
        #expect(stage.settings.toolbarKey(pen) == "!")

        // Space, Return, Tab, Delete, Forward Delete, the arrow keys and a function key type no such character.
        let refused: [(String?, Int)] = [
            (" ", kVK_Space), ("\r", kVK_Return), ("\t", kVK_Tab), ("\u{7F}", kVK_Delete),
            ("\u{F728}", kVK_ForwardDelete), ("\u{F700}", kVK_UpArrow), ("\u{F701}", kVK_DownArrow),
            ("\u{F702}", kVK_LeftArrow), ("\u{F703}", kVK_RightArrow), ("\u{F704}", kVK_F1),
            // A press that types nothing, or more than one character.
            ("", kVK_ANSI_E), (nil, kVK_ANSI_E), ("ab", kVK_ANSI_A),
        ]
        for (typed, keyCode) in refused {
            #expect(stage.record(typed, for: pen, keyCode: keyCode) == true)
            // The recorder stops, the red line tells the rule, and the old key stays.
            #expect(stage.settings.recordingToolbarKey == nil)
            #expect(stage.settings.toolbarKeyProblem == "A toolbar key is one letter, digit or punctuation mark, with no ⌘, ⌃ or ⌥.")
            #expect(stage.settings.toolbarKey(pen) == "!", "typed \(String(describing: typed))")
        }
        // A key with Command, Control or Option is refused.
        for modifiers in [NSEvent.ModifierFlags.command, .control, .option, [.command, .shift]] {
            #expect(stage.record("k", for: pen, keyCode: kVK_ANSI_K, modifiers: modifiers) == true)
            #expect(stage.settings.toolbarKeyProblem == SettingsModel.toolbarKeyNotValidText)
            #expect(stage.settings.toolbarKey(pen) == "!")
        }
        // Esc is not refused: it stops the recorder with no change and no red line (row 5.26).
        #expect(stage.record("\u{1B}", for: pen, keyCode: kVK_Escape) == true)
        #expect(stage.settings.toolbarKeyProblem == nil && stage.settings.toolbarKey(pen) == "!")
        // The store has the last valid key only.
        #expect(ToolbarKeys(defaults: stage.defaults).all[pen] == "!")

        // A new try starts with no old message.
        _ = stage.record(" ", for: pen, keyCode: kVK_Space)
        #expect(stage.settings.toolbarKeyProblem != nil)
        stage.settings.startRecordingToolbarKey(.tool(.arrow))
        #expect(stage.settings.toolbarKeyProblem == nil)
        stage.settings.cancelRecording()
    }

    @Test func row5_22_aKeyOfADifferentActionIsRefused() throws {
        let stage = Stage()
        // H is the key of Highlight. The Arrow cannot take it.
        #expect(stage.record("h", for: .tool(.arrow)) == true)
        #expect(stage.settings.recordingToolbarKey == nil)
        #expect(stage.settings.toolbarKeyProblem == "The key H belongs to Highlight.")
        // The old keys stay, in the window, in the store, on the toolbar and on the overlay.
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)
        #expect(stage.defaults.object(forKey: "toolbarKeys") == nil)
        #expect(try stage.toolbar.button(named: "Arrow").key == "A")
        try stage.type("h")
        #expect(stage.session.tool == .highlight)
        try stage.type("a")
        #expect(stage.session.tool == .arrow)

        // The case does not count, and the key of a different group is refused too.
        #expect(stage.record("S", for: .tool(.pen), modifiers: .shift))
        #expect(stage.settings.toolbarKeyProblem == "The key S belongs to Sticky.")
        #expect(stage.record("4", for: .size(.thin)))
        #expect(stage.settings.toolbarKeyProblem == "The key 4 belongs to Red.")
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)

        // The key that the action has now is accepted: there is no change.
        #expect(stage.record("a", for: .tool(.arrow)))
        #expect(stage.settings.toolbarKeyProblem == nil)
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)

        // A key is free after its action got a different key.
        #expect(stage.record("x", for: .tool(.highlight)))
        #expect(stage.record("h", for: .tool(.arrow)))
        #expect(stage.settings.toolbarKeyProblem == nil)
        #expect(stage.settings.toolbarKey(.tool(.arrow)) == "h" && stage.settings.toolbarKey(.tool(.highlight)) == "x")
        // The start key of the Arrow is free now, but the second key of the Pen is not a key of an action.
        #expect(stage.record("a", for: .tool(.text)))
        #expect(stage.settings.toolbarKeyProblem == nil)
    }

    @Test func row5_23_aValidNewKeyWorksAtOnceAndIsStored() throws {
        let stage = Stage()
        // The settings window opens in click-through (row 5.11). The toolbar shows there.
        stage.controller.toggleClickThrough()
        #expect(try stage.toolbar.button(named: "Arrow").key == "A")

        #expect(stage.record("x", for: .tool(.arrow)) == true)
        #expect(stage.settings.recordingToolbarKey == nil && stage.settings.toolbarKeyProblem == nil)
        #expect(stage.settings.toolbarKey(.tool(.arrow)) == "x")
        // The button shows the new key at once, with no change of the mode.
        #expect(try stage.toolbar.button(named: "Arrow").key == "X")
        #expect(stage.controller.mode == .clickThrough)

        // Back in mode drawing, the new key works and the old key does nothing.
        stage.controller.toggleClickThrough()
        #expect(try stage.toolbar.button(named: "Arrow").key == "X")
        try stage.type("a")
        #expect(stage.session.tool == .pen)
        try stage.type("x")
        #expect(stage.session.tool == .arrow)
        #expect(try stage.selected.contains("Arrow"))

        // A change while the mode is off shows at the next start of drawing.
        stage.controller.toggleDrawing()
        #expect(stage.record("0", for: .size(.thin)))
        stage.controller.toggleDrawing()
        #expect(try stage.toolbar.button(named: "Thin").key == "0")
        try stage.type("0")
        #expect(stage.session.style.size == .thin)

        // It is stored: a later start of the app has the two keys, in the window, on the toolbar and on the overlay.
        let restarted = Stage(defaults: stage.defaults, isOn: false)
        #expect(restarted.settings.toolbarKey(.tool(.arrow)) == "x" && restarted.settings.toolbarKey(.size(.thin)) == "0")
        #expect(restarted.shownKeys == "whxrot023456789fgs")
        restarted.controller.toggleDrawing()
        #expect(try restarted.toolbar.button(named: "Arrow").key == "X")
        #expect(try restarted.toolbar.button(named: "Thin").key == "0")
        try restarted.type("w")
        try restarted.type("x")
        #expect(restarted.session.tool == .arrow)
    }

    @Test func row5_24_resetGivesEachToolbarKeyItsStartValue() throws {
        let stage = Stage()
        let commandF6 = HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: .command)
        stage.settings.startRecording(.draw)
        #expect(stage.settings.keyDown(commandF6))
        #expect(stage.record("x", for: .tool(.pen)))
        #expect(stage.record("w", for: .tool(.arrow)))
        #expect(stage.record("0", for: .color(.white)))
        #expect(stage.record("h", for: .stay(.sticky)))
        #expect(stage.settings.toolbarKeyProblem != nil)
        #expect(stage.shownKeys == "xhwrot123456780fgs")
        #expect(try stage.toolbar.button(named: "Pen").key == "X")

        // The button also stops a recorder that listens.
        stage.settings.startRecordingToolbarKey(.tool(.text))
        stage.settings.resetToolbarKeys()
        #expect(stage.settings.recordingToolbarKey == nil && stage.settings.toolbarKeyProblem == nil)
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)
        #expect(ToolbarAction.all.map { ToolbarKeys(defaults: stage.defaults).all[$0] ?? "" }.joined() == ToolbarKeysTests.startKeys)
        // The toolbar and the overlay have the start keys at once.
        #expect(try stage.toolbar.button(named: "Pen").key == "W")
        #expect(try stage.toolbar.button(named: "White").key == "9")
        try stage.type("a")
        #expect(stage.session.tool == .arrow)
        try stage.type("x")
        #expect(stage.session.tool == .arrow)

        // The two hotkeys do not change, and they work.
        #expect(stage.settings.hotKey(.draw) == commandF6)
        #expect(stage.settings.hotKey(.clickThrough) == HotKeyKind.clickThrough.startValue)
        #expect(SettingsStore(defaults: stage.defaults).hotKey(.draw) == commandF6)
        #expect(stage.hotKeys.registered == [.draw: commandF6, .clickThrough: HotKeyKind.clickThrough.startValue])
        // A second reset changes nothing.
        stage.settings.resetToolbarKeys()
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)
    }

    @Test func row5_25_storedKeysThatAreNotValidGiveTheStartKeys() throws {
        let defaults = MemoryDefaults()
        let keys = ToolbarKeys(defaults: defaults)
        func shown() -> String {
            ToolbarAction.all.map { keys.all[$0] ?? "?" }.joined()
        }
        // Nothing is stored: the start keys.
        #expect(shown() == ToolbarKeysTests.startKeys)

        // Valid stored keys are used. An action with no stored key has its start key. A capital letter is its letter.
        defaults.set(["tool.pen": "x", "color.white": "0", "stay.fade": "K"], forKey: "toolbarKeys")
        #expect(shown() == "xharot123456780kgs")
        #expect(keys.action(for: "x") == .tool(.pen) && keys.action(for: "k") == .stay(.fade))
        // A name that is not an action is not used.
        defaults.set(["tool.pen": "x", "tool.eraser": "e"], forKey: "toolbarKeys")
        #expect(shown() == "xharot123456789fgs")
        #expect(keys.action(for: "e") == nil)

        let broken: [Any] = [
            "wharot",                                   // not a table
            ["w", "h"],                                 // not a table
            42,
            ["tool.pen": 7],                            // the key is not a text
            ["tool.pen": "x", "tool.arrow": 7],         // one key is not a text
            ["tool.pen": ""],                           // no character
            ["tool.pen": "xy"],                         // two characters
            ["tool.pen": " "],                          // Space
            ["tool.pen": "\r"],                         // Return
            ["tool.pen": "\t"],                         // Tab
            ["tool.pen": "\u{1B}"],                     // Esc
            ["tool.pen": "\u{7F}"],                     // Delete
            ["tool.pen": "\u{F700}"],                   // an arrow key
            ["tool.pen": "x", "tool.arrow": "x"],       // two stored keys are the same
            ["tool.pen": "X", "tool.arrow": "x"],       // the same letter
            ["tool.pen": "h"],                          // the start key of Highlight, which has no stored key
            ["tool.pen": "x", "size.thin": "9"],        // the start key of White
        ]
        for value in broken {
            defaults.set(value, forKey: "toolbarKeys")
            // All the start keys, also for an action whose stored key is valid.
            #expect(shown() == ToolbarKeysTests.startKeys, "\(value)")
            #expect(keys.action(for: "w") == .tool(.pen) && keys.action(for: "x") == nil, "\(value)")
        }

        // The app with such a value: the window, the toolbar and the overlay use the start keys.
        defaults.set(["tool.pen": "x", "tool.arrow": "x"], forKey: "toolbarKeys")
        let restarted = Stage(defaults: defaults, isOn: false)
        #expect(restarted.shownKeys == ToolbarKeysTests.startKeys)
        restarted.controller.toggleDrawing()
        #expect(try restarted.toolbar.button(named: "Pen").key == "W")
        try restarted.type("a")
        #expect(restarted.session.tool == .arrow)
        try restarted.type("x")
        #expect(restarted.session.tool == .arrow)
        // The next valid change stores a full valid table.
        #expect(restarted.record("x", for: .tool(.arrow)))
        #expect(restarted.shownKeys == "whxrot123456789fgs")
        #expect((restarted.defaults.object(forKey: "toolbarKeys") as? [String: String])?.count == 18)
    }

    @Test func row5_26_theRecorderOfAToolbarKeyPausesTheTwoHotKeysAndEscStopsIt() {
        let stage = Stage(isOn: false)
        var pressed: [HotKeyKind] = []
        stage.hotKeys.onHotKey = { pressed.append($0) }
        let escape = HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [])
        let controlOptionD = HotKeyKind.draw.startValue, controlOptionC = HotKeyKind.clickThrough.startValue

        // A key in the window while nothing records is not for the model.
        #expect(stage.settings.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_X), modifiers: []), characters: "x") == false)

        stage.settings.startRecordingToolbarKey(.tool(.pen))
        #expect(stage.settings.recordingToolbarKey == .tool(.pen) && stage.settings.recording == nil)
        // The two hotkeys are paused: a press changes no mode.
        #expect(stage.hotKeys.registered.isEmpty)
        stage.hotKeys.press(controlOptionD)
        stage.hotKeys.press(controlOptionC)
        #expect(pressed.isEmpty)

        // Esc stops the recorder with no change, also with a modifier. The two hotkeys work again.
        #expect(stage.settings.keyDown(escape, characters: "\u{1B}") == true)
        #expect(stage.settings.recordingToolbarKey == nil && stage.settings.toolbarKeyProblem == nil)
        #expect(stage.shownKeys == ToolbarKeysTests.startKeys)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
        stage.settings.startRecordingToolbarKey(.tool(.pen))
        #expect(stage.settings.keyDown(HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: .command), characters: "\u{1B}") == true)
        #expect(stage.settings.recordingToolbarKey == nil && stage.shownKeys == ToolbarKeysTests.startKeys)

        // The hotkeys work again after a valid key and after a refused key.
        #expect(stage.record("x", for: .tool(.pen)))
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
        #expect(stage.record("h", for: .tool(.pen)))
        #expect(stage.settings.toolbarKeyProblem != nil)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
        stage.hotKeys.press(controlOptionD)
        #expect(pressed == [.draw])

        // Only one recorder listens: a different key, or a hotkey row, takes the recorder.
        stage.settings.startRecordingToolbarKey(.tool(.pen))
        stage.settings.startRecordingToolbarKey(.color(.red))
        #expect(stage.settings.recordingToolbarKey == .color(.red))
        stage.settings.startRecording(.draw)
        #expect(stage.settings.recording == .draw && stage.settings.recordingToolbarKey == nil)
        #expect(stage.hotKeys.registered.isEmpty)
        stage.settings.startRecordingToolbarKey(.stay(.hold))
        #expect(stage.settings.recording == nil && stage.settings.recordingToolbarKey == .stay(.hold))
        #expect(stage.hotKeys.registered.isEmpty)
        // The key goes to the toolbar key, not to the hotkey row.
        #expect(stage.settings.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: []), characters: "k"))
        #expect(stage.settings.toolbarKey(.stay(.hold)) == "k")
        #expect(stage.settings.hotKey(.draw) == controlOptionD && stage.settings.hotKeyProblem(.draw) == nil)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)

        // The window loses the keyboard or closes while a toolbar key records: the same as Esc.
        let window = SettingsWindowController(model: stage.settings)
        window.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        stage.settings.startRecordingToolbarKey(.size(.thin))
        #expect(stage.hotKeys.registered.isEmpty)
        window.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(stage.settings.recordingToolbarKey == nil && window.keyMonitor == nil)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
        stage.settings.startRecordingToolbarKey(.size(.thin))
        window.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(stage.settings.recordingToolbarKey == nil)
        #expect(stage.hotKeys.registered == ToolbarKeysTests.bothHotKeys)
    }

    @Test func row5_27_theSettingsWindowIsNotHigherThan640Points() {
        let stage = Stage(isOn: false)
        @MainActor func size() -> CGSize {
            NSHostingView(rootView: SettingsView(model: stage.settings)).fittingSize
        }
        let plain = size()
        #expect(plain.width == 460)
        #expect(plain.height <= 640)

        // The highest form: each red line shows, and a recorder listens.
        let loginItem = FakeLoginItem()
        loginItem.refuses = true
        let hotKeys = FakeHotKeyRegistrar()
        hotKeys.refused = [HotKeyKind.draw.startValue, HotKeyKind.clickThrough.startValue]
        let full = SettingsModel(store: SettingsStore(defaults: MemoryDefaults()), hotKeys: hotKeys, loginItem: loginItem)
        full.registerHotKeys()
        full.setOpenAtLogin(true)
        full.startRecordingToolbarKey(.tool(.arrow))
        _ = full.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: .command), characters: "h")
        #expect(full.hotKeyProblem(.draw) != nil && full.hotKeyProblem(.clickThrough) != nil)
        #expect(full.loginItemProblem != nil && full.toolbarKeyProblem == SettingsModel.toolbarKeyNotValidText)
        let highest = NSHostingView(rootView: SettingsView(model: full)).fittingSize
        #expect(highest.height > plain.height)
        #expect(highest.height <= 640)
    }
}
