import AppKit

/// The 21 actions of the toolbar that have a key (D11, row 2.61): the nine tools, the three sizes,
/// the six colours and the three values of the switch. Undo, Redo, Clear all and Close have fixed keys.
enum ToolbarAction: Hashable {
    case tool(Tool)
    case size(MarkSize)
    case color(MarkColor)
    case stay(StayMode)

    /// The four groups, in the order of the toolbar. The settings window shows them in this order.
    static let groups: [(title: String, actions: [ToolbarAction])] = [
        ("Tools", Tool.allCases.map { .tool($0) }),
        ("Sizes", MarkSize.allCases.map { .size($0) }),
        ("Colours", MarkColor.allCases.map { .color($0) }),
        ("Stay", StayMode.allCases.map { .stay($0) }),
    ]

    static let all = groups.flatMap { $0.actions }

    /// The name of the button.
    var name: String {
        switch self {
        case .tool(let tool): return tool.name
        case .size(let size): return size.name
        case .color(let color): return color.name
        case .stay(let stay): return stay.name
        }
    }

    /// The name of the action in the stored value.
    var id: String {
        switch self {
        case .tool(let tool): return "tool." + tool.rawValue
        case .size(let size): return "size." + size.rawValue
        case .color(let color): return "color." + color.rawValue
        case .stay(let stay): return "stay." + stay.rawValue
        }
    }

    /// The key at the start (D11, D14, D15): the letters of the draw app for the tools, 1 to 3
    /// for the sizes, 4 to 9 for the colours, and F, G, S for the switch.
    var startKey: String {
        switch self {
        case .tool(.select): return "v"
        case .tool(.pen): return "w"
        case .tool(.highlight): return "h"
        case .tool(.line): return "d"
        case .tool(.arrow): return "a"
        case .tool(.rectangle): return "r"
        case .tool(.ellipse): return "o"
        case .tool(.text): return "t"
        case .tool(.stamp): return "n"
        case .size(.thin): return "1"
        case .size(.medium): return "2"
        case .size(.thick): return "3"
        case .color(.red): return "4"
        case .color(.amber): return "5"
        case .color(.green): return "6"
        case .color(.blue): return "7"
        case .color(.black): return "8"
        case .color(.white): return "9"
        case .stay(.fade): return "f"
        case .stay(.hold): return "g"
        case .stay(.sticky): return "s"
        }
    }
}

/// The keys of the toolbar (D11), in `UserDefaults`. A key is one character, in lower case.
///
/// This is the one store that the shell and the drawing part share. The settings window writes a
/// key here. The overlay reads the keys when a key arrives, and the toolbar reads them to show
/// them. Each side makes its own `ToolbarKeys` on the same `UserDefaults`. Thus the shell does not
/// know the session or the toolbar, and a new key works at once with no message between the two.
///
/// The keys are not global hotkeys. Nothing is registered for them, so they cost nothing while
/// the mode is off. The store never fails: stored keys that are not valid give the start keys.
struct ToolbarKeys {
    /// The second key of the Pen, as in the draw app. It works only while no action has this key (row 2.31).
    static let secondPenKey = "p"
    /// The second key of the Line, as in the draw app. It works only while no action has this key (row 2.51).
    static let secondLineKey = "l"
    private static let defaultsKey = "toolbarKeys"

    let defaults: UserDefaults

    /// The toolbar key that a key press types. `nil` when the press is not a toolbar key.
    ///
    /// The key is the character that the press types, not the position on the keyboard (row 2.39).
    /// The case of a letter does not count, so Shift and Caps Lock change nothing (row 2.36).
    /// A press with Command, Control or Option is not a toolbar key (rows 2.35 and 5.21).
    /// Space, Return, Tab, Esc, Delete, an arrow key and a function key type no letter, digit or
    /// punctuation mark, so they are not toolbar keys (row 5.21).
    static func key(typed characters: String?, modifiers: NSEvent.ModifierFlags = []) -> String? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let key = characters?.lowercased(), key.count == 1, let character = key.first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return nil }
        return key
    }

    /// The key of each action now.
    var all: [ToolbarAction: String] {
        var keys: [ToolbarAction: String] = [:]
        for action in ToolbarAction.all { keys[action] = action.startKey }
        guard let stored = defaults.object(forKey: ToolbarKeys.defaultsKey) as? [String: String] else { return keys }
        let start = keys
        for action in ToolbarAction.all {
            guard let value = stored[action.id] else { continue }
            // A stored key that is not valid: the app uses the start keys (row 5.25).
            guard let key = ToolbarKeys.key(typed: value) else { return start }
            keys[action] = key
        }
        // Two actions with the same key: the app uses the start keys (row 5.25).
        return Set(keys.values).count == keys.count ? keys : start
    }

    /// The action of a typed key, if the key is a toolbar key now.
    func action(for key: String) -> ToolbarAction? {
        let keys = all
        if let action = ToolbarAction.all.first(where: { keys[$0] == key }) { return action }
        switch key {
        case ToolbarKeys.secondPenKey: return .tool(.pen)
        case ToolbarKeys.secondLineKey: return .tool(.line)
        default: return nil
        }
    }

    /// Stores a new key for one action. The caller makes sure that the key is valid and that no
    /// other action has it (rows 5.21 and 5.22).
    func set(_ key: String, for action: ToolbarAction) {
        var stored: [String: String] = [:]
        for (each, value) in all { stored[each.id] = value }
        stored[action.id] = key
        defaults.set(stored, forKey: ToolbarKeys.defaultsKey)
    }

    /// "Reset to the start keys" (row 5.24).
    func reset() {
        defaults.removeObject(forKey: ToolbarKeys.defaultsKey)
    }
}
