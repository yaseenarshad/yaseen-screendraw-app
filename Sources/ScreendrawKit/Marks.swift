import CoreGraphics

// The model of the marks that the user draws on a screen. No drawing here: `MarkRenderer` draws.

/// The six tools, in the order of the toolbar (D5).
enum Tool: String, Hashable, CaseIterable {
    case pen, highlight, arrow, rectangle, ellipse, text

    var name: String {
        switch self {
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        }
    }
}

enum MarkSize: String, Hashable, CaseIterable {
    case thin, medium, thick

    var name: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }
}

enum MarkColor: String, Hashable, CaseIterable {
    case red, amber, green, blue, black, white

    var name: String {
        switch self {
        case .red: return "Red"
        case .amber: return "Amber"
        case .green: return "Green"
        case .blue: return "Blue"
        case .black: return "Black"
        case .white: return "White"
        }
    }

    /// The colour in sRGB, each part from 0 to 1.
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: return (1.0, 0.23, 0.19)
        case .amber: return (1.0, 0.70, 0.0)
        case .green: return (0.20, 0.78, 0.35)
        case .blue: return (0.0, 0.48, 1.0)
        case .black: return (0, 0, 0)
        case .white: return (1, 1, 1)
        }
    }
}

/// How long a mark stays on the screen (D6).
enum StayMode: String, Hashable, CaseIterable {
    /// The mark goes away a short time after it is finished.
    case fade
    /// The mark stays while the user draws. All Hold marks go away together after the last drawing activity.
    case hold
    /// The mark stays until the user clears it.
    case sticky

    var name: String {
        switch self {
        case .fade: return "Fade"
        case .hold: return "Hold"
        case .sticky: return "Sticky"
        }
    }
}

/// The colour and the size of a mark.
struct MarkStyle: Equatable {
    var color: MarkColor
    var size: MarkSize

    /// The width of the line in points. Highlight is a wide line.
    func lineWidth(for tool: Tool) -> CGFloat {
        switch (tool == .highlight, size) {
        case (false, .thin): return 2
        case (false, .medium): return 4
        case (false, .thick): return 7
        case (true, .thin): return 10
        case (true, .medium): return 16
        case (true, .thick): return 24
        }
    }

    /// The size of the font of a Text mark, in points.
    var fontSize: CGFloat {
        switch size {
        case .thin: return 14
        case .medium: return 18
        case .thick: return 24
        }
    }
}

/// One mark. Its points are in the points of its screen: the top-left of the screen is 0, 0.
struct Mark: Equatable {
    let tool: Tool
    var style: MarkStyle
    /// Rectangle, Ellipse and Arrow: the start and the end of the drag.
    /// Pen and Highlight: the path of the pointer. Text: the top-left of the text.
    var points: [CGPoint]
    /// Only for Text.
    var text = ""
    /// Only for Text: a line breaks at this width.
    var wrapWidth: CGFloat = 0
}
