import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ScreendrawKit

/// Fade seconds and Hold seconds in Settings (D12, YAZ-2826), out of sight: rows 3.20 to 3.26.
///
/// The stage has the real settings model and a real session on one `MemoryDefaults`, as the app
/// has them on `UserDefaults.standard`. The test sets the clock. No test sleeps.
@MainActor @Suite struct MarkSecondsTests {
    @MainActor final class Stage {
        let clock = TestClock()
        let defaults: MemoryDefaults
        let settings: SettingsModel
        let session: DrawSession

        /// A stage on the `defaults` of an earlier stage is a later start of the app.
        init(defaults: MemoryDefaults = MemoryDefaults()) {
            self.defaults = defaults
            settings = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeyRegistrar(), loginItem: FakeLoginItem())
            session = DrawSession(prefs: DrawPrefs(defaults: defaults), now: { [clock] in clock.time })
            session.start(displays: [Screens.left, Screens.right])
        }

        /// One line with the given stay value. Returns the mark.
        func draw(_ stay: StayMode, row: Int = 0) throws -> PlacedMark {
            session.setStay(stay)
            session.drawLine(row: row)
            return try #require(session.allMarks.last)
        }

        /// How strong the mark with this id shows now. `nil` when the mark is gone.
        func strength(_ placed: PlacedMark) -> CGFloat? {
            session.tick()
            return session.allMarks.first { $0.id == placed.id }.map { session.opacity(of: $0) }
        }
    }

    private func formSize(_ model: SettingsModel) -> CGSize {
        NSHostingView(rootView: SettingsView(model: model)).fittingSize
    }

    private func isNear(_ a: CGFloat?, _ b: CGFloat) -> Bool {
        a.map { abs($0 - b) < 0.0001 } ?? false
    }

    @Test func row3_20_theSettingsHaveThePartMarksWithFadeSecondsAndHoldSeconds() throws {
        let stage = Stage()
        // The start values are 2 and 5, in the window and in the drawing part.
        #expect(stage.settings.fadeSeconds == 2 && stage.settings.holdSeconds == 5)
        #expect(DrawPrefs.firstFadeSeconds == 2 && DrawPrefs.firstHoldSeconds == 5)
        #expect(DrawSession.fadeTime == 2 && DrawSession.holdTime == 5)
        #expect(stage.settings.secondsProblem == nil)
        // Nothing is stored before the user changes a value.
        #expect(stage.defaults.values.isEmpty)

        // The form is 460 points wide and not higher than 640 points with the new part (row 5.27).
        let plain = formSize(stage.settings)
        #expect(plain.width == 460 && plain.height <= 640)
        // The part has its own red line: a refused value makes the form higher.
        stage.settings.setFadeSeconds("0")
        let refused = formSize(stage.settings)
        #expect(refused.height > plain.height)

        // The highest form: each red line of the window shows at the same time.
        let loginItem = FakeLoginItem()
        loginItem.refuses = true
        let hotKeys = FakeHotKeyRegistrar()
        hotKeys.refused = [HotKeyKind.draw.startValue, HotKeyKind.clickThrough.startValue]
        let full = SettingsModel(store: SettingsStore(defaults: MemoryDefaults()), hotKeys: hotKeys, loginItem: loginItem)
        full.registerHotKeys()
        full.setOpenAtLogin(true)
        full.setHoldSeconds("")
        full.startRecordingToolbarKey(.tool(.arrow))
        _ = full.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: .command), characters: "h")
        #expect(full.hotKeyProblem(.draw) != nil && full.hotKeyProblem(.clickThrough) != nil && full.loginItemProblem != nil)
        #expect(full.secondsProblem != nil && full.toolbarKeyProblem != nil)
        let highest = formSize(full)
        // The form stops at 610 points, so the window with its title bar of 28 points stays below
        // 640 points. The form is a scroll area of that size, so the rows below its edge are in reach.
        #expect(highest.height > refused.height && highest.height == 610)
        let host = NSHostingView(rootView: SettingsView(model: full))
        host.frame = CGRect(origin: .zero, size: highest)
        host.layoutSubtreeIfNeeded()
        func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { ($0 as? NSScrollView).map { [$0] } ?? scrollViews(in: $0) }
        }
        #expect(scrollViews(in: host).first?.frame.size == highest)

        // The pictures for the review: the form, the form in dark mode, and a refused value.
        stage.settings.setFadeSeconds("2")
        try picture(of: stage.settings).write("v020-settings.png")
        try picture(of: stage.settings, appearance: .darkAqua).write("v020-settings-dark.png")
        stage.settings.setFadeSeconds("61")
        try picture(of: stage.settings).write("v020-settings-refused.png")
        try picture(of: full).write("v020-settings-highest.png")
    }

    /// The form of the settings window as a picture, with no window.
    private func picture(of model: SettingsModel, appearance: NSAppearance.Name = .aqua) throws -> Snapshot {
        let view = NSHostingView(rootView: SettingsView(model: model))
        view.appearance = NSAppearance(named: appearance)
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        return try Snapshot(of: view)
    }

    @Test func row3_21_aWholeNumberFrom1To60IsStoredAndStaysAfterARestart() throws {
        let stage = Stage()
        // The two ends of the range, and a value between them. Spaces around the number do not count.
        for (text, seconds) in [("1", 1), ("60", 60), ("7", 7), (" 12 ", 12), ("03", 3)] {
            stage.settings.setFadeSeconds(text)
            #expect(stage.settings.fadeSeconds == seconds && stage.settings.secondsProblem == nil, "Fade \(text)")
            #expect(stage.defaults.object(forKey: "drawFadeSeconds") as? Int == seconds)
            stage.settings.setHoldSeconds(text)
            #expect(stage.settings.holdSeconds == seconds && stage.settings.secondsProblem == nil, "Hold \(text)")
            #expect(stage.defaults.object(forKey: "drawHoldSeconds") as? Int == seconds)
        }
        // The two values are different values.
        stage.settings.setFadeSeconds("4")
        stage.settings.setHoldSeconds("30")
        #expect(stage.settings.fadeSeconds == 4 && stage.settings.holdSeconds == 30)
        // They are next to the other values of the drawing part, and the app stores no other new value.
        stage.session.setStay(.hold)
        #expect(Set(stage.defaults.values.keys) == ["drawFadeSeconds", "drawHoldSeconds", "drawStayMode"])

        // A later start of the app: the window and the drawing part have the two values.
        let restarted = Stage(defaults: stage.defaults)
        #expect(restarted.settings.fadeSeconds == 4 && restarted.settings.holdSeconds == 30)
        let fade = try restarted.draw(.fade)
        #expect(fade.fadeTime == 4)
        restarted.clock.time += 2.9
        #expect(restarted.strength(fade) == 1)
        restarted.clock.time += 0.6
        #expect(isNear(restarted.strength(fade), 0.5))
    }

    @Test func row3_22_anEmptyFieldZero61OrALetterIsRefusedWithARedLine() throws {
        let stage = Stage()
        stage.settings.setFadeSeconds("9")
        stage.settings.setHoldSeconds("20")
        let stored = stage.defaults.values.count

        for text in ["", " ", "0", "61", "x", "abc", "-1", "2.5", "1e1", "7 seconds", "999999999999999999999"] {
            stage.settings.setFadeSeconds(text)
            // The red line tells the rule, and the old value stays in the window and in the store.
            #expect(stage.settings.secondsProblem == "Fade seconds must be a whole number from 1 to 60.", "Fade \"\(text)\"")
            #expect(stage.settings.fadeSeconds == 9 && stage.defaults.object(forKey: "drawFadeSeconds") as? Int == 9)

            stage.settings.setHoldSeconds(text)
            #expect(stage.settings.secondsProblem == "Hold seconds must be a whole number from 1 to 60.", "Hold \"\(text)\"")
            #expect(stage.settings.holdSeconds == 20 && stage.defaults.object(forKey: "drawHoldSeconds") as? Int == 20)
        }
        #expect(stage.defaults.values.count == stored)
        // The drawing part still uses the old values.
        let fade = try stage.draw(.fade)
        #expect(fade.fadeTime == 9)

        // The next valid value removes the red line.
        stage.settings.setHoldSeconds("21")
        #expect(stage.settings.secondsProblem == nil && stage.settings.holdSeconds == 21)
        // A refused value does not change the two hotkeys or the keys of the toolbar.
        #expect(stage.settings.toolbarKeyProblem == nil && stage.settings.hotKeyProblem(.draw) == nil)
    }

    @Test func row3_23_aFadeMarkIsFullForNMinus1SecondsAndThenFadesFor1Second() throws {
        for seconds in [1, 2, 3, 10, 60] {
            let stage = Stage()
            stage.settings.setFadeSeconds(String(seconds))
            let mark = try stage.draw(.fade)
            let full = TimeInterval(seconds - 1)
            #expect(stage.strength(mark) == 1, "\(seconds) s")
            if seconds > 1 {
                // Full strength until N minus 1 seconds.
                stage.clock.time += full - 0.01
                #expect(stage.strength(mark) == 1, "\(seconds) s")
                stage.clock.time += 0.01
                #expect(isNear(stage.strength(mark), 1), "\(seconds) s")
            }
            // Then it fades for 1 second. With N = 1, it fades from the start.
            stage.clock.time += 0.25
            #expect(isNear(stage.strength(mark), 0.75), "\(seconds) s")
            stage.clock.time += 0.5
            #expect(isNear(stage.strength(mark), 0.25), "\(seconds) s")
            #expect(stage.session.hasTimedMarks)
            // At N seconds the mark is removed.
            stage.clock.time += 0.2501
            #expect(stage.strength(mark) == nil && stage.session.markCount == 0, "\(seconds) s")
            #expect(!stage.session.hasTimedMarks)
        }
    }

    @Test func row3_24_theHoldMarksAreFullUntilNSecondsAfterTheLastActivityAndThenFadeTogether() throws {
        for seconds in [1, 5, 8, 60] {
            let stage = Stage()
            stage.settings.setHoldSeconds(String(seconds))
            let first = try stage.draw(.hold, row: 0)
            stage.clock.time += 0.5
            // The second mark is the last drawing activity: the N seconds start again for the two marks.
            let second = try stage.draw(.hold, row: 1)
            stage.clock.time += TimeInterval(seconds) - 0.01
            #expect(stage.strength(first) == 1 && stage.strength(second) == 1, "\(seconds) s")
            stage.clock.time += 0.01
            #expect(isNear(stage.strength(first), 1) && isNear(stage.strength(second), 1), "\(seconds) s")
            // Then they fade together for 1 second.
            stage.clock.time += 0.5
            #expect(isNear(stage.strength(first), 0.5) && isNear(stage.strength(second), 0.5), "\(seconds) s")
            stage.clock.time += 0.5001
            #expect(stage.strength(first) == nil && stage.strength(second) == nil, "\(seconds) s")
            #expect(stage.session.markCount == 0)
        }
    }

    @Test func row3_25_aFadeMarkKeepsItsTimeAndTheHoldMarksUseTheNewValueAtOnce() throws {
        let stage = Stage()
        // Fade is 2 seconds and Hold is 5 seconds. One mark of each kind is on the screen.
        let oldFade = try stage.draw(.fade, row: 0)
        let hold = try stage.draw(.hold, row: 1)
        stage.clock.time += 0.5

        // The user changes the two values in Settings while the marks show.
        stage.settings.setFadeSeconds("10")
        stage.settings.setHoldSeconds("1")
        let newFade = try stage.draw(.fade, row: 2)
        #expect(oldFade.fadeTime == 2 && newFade.fadeTime == 10)
        // The last drawing activity is now. The Hold mark uses the new value at once: 1 second.
        stage.clock.time += 1
        #expect(stage.strength(hold) == 1)
        stage.clock.time += 0.5
        #expect(isNear(stage.strength(hold), 0.5))
        // The old Fade mark keeps the 2 seconds that it was drawn with: it is gone at 2 seconds.
        #expect(stage.strength(oldFade) == nil)
        // The new Fade mark has the 10 seconds.
        #expect(stage.strength(newFade) == 1)
        stage.clock.time += 0.5
        #expect(stage.strength(hold) == nil)

        // A longer Hold value also applies at once to the Hold marks that are on the screen.
        let secondHold = try stage.draw(.hold, row: 3)
        stage.clock.time += 1.5
        #expect(isNear(stage.strength(secondHold), 0.5))
        stage.settings.setHoldSeconds("30")
        #expect(stage.strength(secondHold) == 1)
        stage.clock.time += 28.5
        #expect(stage.strength(secondHold) == 1)
        stage.clock.time += 0.5
        #expect(isNear(stage.strength(secondHold), 0.5))

        // Undo and Redo bring a Fade mark back with the time that it was drawn with (row 3.11).
        stage.clock.time = 5000
        stage.settings.setFadeSeconds("3")
        let third = try stage.draw(.fade, row: 4)
        stage.settings.setFadeSeconds("20")
        stage.session.undo()
        stage.session.redo()
        #expect(stage.session.allMarks.first { $0.id == third.id }?.fadeTime == 3)
    }

    @Test func row3_26_aStoredValueThatIsNotValidGivesTheStartValue() throws {
        let broken: [Any] = [0, 61, -3, 1000, "7", "abc", 2.5, ["a"], Date(timeIntervalSince1970: 0)]
        for value in broken {
            let defaults = MemoryDefaults()
            defaults.set(value, forKey: "drawFadeSeconds")
            defaults.set(value, forKey: "drawHoldSeconds")
            #expect(DrawPrefs(defaults: defaults).fadeSeconds == 2 && DrawPrefs(defaults: defaults).holdSeconds == 5, "\(value)")

            // The window shows the start values, and the drawing part uses them.
            let stage = Stage(defaults: defaults)
            #expect(stage.settings.fadeSeconds == 2 && stage.settings.holdSeconds == 5, "\(value)")
            let fade = try stage.draw(.fade)
            #expect(fade.fadeTime == 2, "\(value)")
            stage.clock.time += 1.5
            #expect(isNear(stage.strength(fade), 0.5), "\(value)")
        }
        // One value that is not valid does not change the other value.
        let defaults = MemoryDefaults()
        defaults.set(99, forKey: "drawFadeSeconds")
        defaults.set(9, forKey: "drawHoldSeconds")
        #expect(DrawPrefs(defaults: defaults).fadeSeconds == 2 && DrawPrefs(defaults: defaults).holdSeconds == 9)
        // The ends of the range are valid.
        defaults.set(1, forKey: "drawFadeSeconds")
        defaults.set(60, forKey: "drawHoldSeconds")
        #expect(DrawPrefs(defaults: defaults).fadeSeconds == 1 && DrawPrefs(defaults: defaults).holdSeconds == 60)
    }
}
