import AppKit

/// Shows a `Mark` as a Core Animation layer.
///
/// The mark of the drag in progress and the finished marks both use this code, so a mark does
/// not change its look when the pointer is released. The paths have the top-left of the screen
/// at 0, 0, with y going down and one unit for one point.
enum MarkRenderer {
    /// Highlight lets this part of its colour show, so the screen below stays readable.
    static let highlightAlpha: CGFloat = 0.4

    /// No implicit animation: a line must follow the pointer at once, and a fade is set by the clock.
    static let noActions: [String: CAAction] = [
        "path": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "contents": NSNull(),
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "sublayers": NSNull(),
        "strokeColor": NSNull(), "fillColor": NSNull(), "lineWidth": NSNull(),
        "lineCap": NSNull(), "lineJoin": NSNull(),
    ]

    static func color(_ color: MarkColor, alpha: CGFloat = 1) -> CGColor {
        let parts = color.components
        return CGColor(srgbRed: parts.red, green: parts.green, blue: parts.blue, alpha: alpha)
    }

    /// The layer of a finished mark. `scale` is the scale of the screen, for a sharp Text.
    static func makeLayer(for mark: Mark, scale: CGFloat) -> CALayer {
        if mark.tool == .text {
            return makeTextLayer(for: mark, scale: scale)
        }
        let layer = CAShapeLayer()
        layer.actions = noActions
        show(mark, in: layer)
        if mark.tool == .stamp {
            layer.addSublayer(makeNumberLayer(for: mark))
        }
        return layer
    }

    /// Shows a mark in a shape layer. Each tool but Text is one path: a line or a filled shape.
    /// A drag gives its own `line`, so each new point of a Pen line adds only one curve.
    static func show(_ mark: Mark, in layer: CAShapeLayer, line: SmoothLine = SmoothLine()) {
        let isHighlight = mark.tool == .highlight
        let isFilled = mark.tool == .arrow || mark.tool == .stamp
        let color = MarkRenderer.color(mark.style.color, alpha: isHighlight ? highlightAlpha : 1)
        layer.path = path(for: mark, line: line)
        layer.lineWidth = mark.lineWidth
        // The Arrow and the Stamp are filled shapes. Each other tool is a line with no fill.
        layer.strokeColor = isFilled ? nil : color
        layer.fillColor = isFilled ? color : nil
        layer.lineCap = mark.tool == .pen || mark.tool == .line ? .round : .butt
        layer.lineJoin = mark.tool == .rectangle ? .miter : .round
    }

    // MARK: Shapes

    static func path(for mark: Mark, line: SmoothLine = SmoothLine()) -> CGPath {
        let path = CGMutablePath()
        guard let first = mark.points.first, let last = mark.points.last else { return path }
        switch mark.tool {
        case .pen where mark.points.count == 1:
            // A click with no move: a line with round ends and almost no length is a dot.
            path.move(to: first)
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
        case .pen, .highlight:
            return line.path(through: mark.points)
        case .line where mark.points.count > 1:
            path.move(to: first)
            path.addLine(to: last)
        case .rectangle where mark.points.count > 1:
            path.addRect(mark.frame)
        case .ellipse where mark.points.count > 1:
            path.addEllipse(in: mark.frame)
        case .arrow:
            addArrow(mark, from: first, to: path)
        case .stamp:
            path.addEllipse(in: mark.bounds)
        default:
            break
        }
        return path
    }

    /// The outline of an arrow: a line with a round start, and a head at the end of the drag.
    /// It is one closed shape, so the layer fills it and draws no line.
    private static func addArrow(_ mark: Mark, from start: CGPoint, to path: CGMutablePath) {
        guard let head = mark.arrowHead else { return }
        path.move(to: head.tip)
        path.addLine(to: head.left)
        if head.hasShaft {
            // Along one side of the line, around the round start, and back along the other side.
            let halfLine = min(mark.lineWidth / 2, head.halfWidth)
            let angle = atan2(head.direction.y, head.direction.x)
            path.addLine(to: head.beside(head.base, -halfLine))
            path.addLine(to: head.beside(start, -halfLine))
            path.addArc(center: start, radius: halfLine, startAngle: angle - .pi / 2, endAngle: angle - 3 * .pi / 2, clockwise: true)
            path.addLine(to: head.beside(head.base, halfLine))
        }
        path.addLine(to: head.right)
        path.closeSubpath()
    }

    // MARK: Stamp

    /// The colour of the number of a Stamp: white on a dark circle, black on a light circle, so
    /// the number is easy to read on each of the six colours (row 2.57).
    static func numberColor(on color: MarkColor) -> CGColor {
        switch color {
        case .red, .blue, .black: return CGColor(gray: 1, alpha: 1)
        case .amber, .green, .white: return CGColor(gray: 0, alpha: 1)
        }
    }

    /// The number of a Stamp, as the outlines of its digits in the middle of the circle. A path
    /// is sharp at each scale, and a fade of the Stamp also fades it.
    private static func makeNumberLayer(for mark: Mark) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.actions = noActions
        layer.fillColor = numberColor(on: mark.style.color)
        guard let middle = mark.points.first else { return layer }

        let diameter = mark.style.stampDiameter
        let font = NSFont.systemFont(ofSize: diameter * 0.6, weight: .bold) as CTFont
        let text = NSAttributedString(string: String(mark.number), attributes: [.font: font])
        let digits = CGMutablePath()
        for run in CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var places = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &places)
            for (glyph, place) in zip(glyphs, places) {
                guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                digits.addPath(outline, transform: CGAffineTransform(translationX: place.x, y: place.y))
            }
        }
        // A number with many digits gets smaller, so it stays in the circle.
        let box = digits.boundingBoxOfPath
        guard !box.isEmpty else { return layer }
        let scale = min(1, diameter * 0.7 / box.width)
        // The digits have y going up, and the layer of the marks has y going down.
        var toMiddle = CGAffineTransform(translationX: middle.x, y: middle.y)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        layer.path = digits.copy(using: &toMiddle)
        return layer
    }

    // MARK: Text

    static func textAttributes(_ style: MarkStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: color(style.color)) ?? .red,
        ]
    }

    /// A Text mark is an image of its lines, made one time. Thus an emoji keeps its colours.
    private static func makeTextLayer(for mark: Mark, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.actions = noActions
        let layout = TextLayout(text: mark.text, style: mark.style, wrapWidth: mark.wrapWidth)
        let used = layout.usedRect
        let size = CGSize(width: ceil(used.maxX), height: ceil(used.maxY))
        guard
            let origin = mark.points.first, size.width > 0, size.height > 0,
            let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return layer }

        // The text system draws with y going down, from the top-left of the image.
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        layout.manager.drawGlyphs(forGlyphRange: layout.manager.glyphRange(for: layout.container), at: .zero)
        NSGraphicsContext.current = previous

        layer.contents = context.makeImage()
        layer.contentsScale = scale
        layer.frame = CGRect(origin: origin, size: size)
        // The layer of the marks is turned over, so y goes down. An image is upside down there.
        // This layer turns its image back.
        layer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
        return layer
    }
}

/// A smooth line through the points of the pointer: each point is the control point of a curve
/// between the middles of its two segments.
///
/// A drag adds one point at a time. The line keeps the curves that it has, and a new point adds
/// one curve. A finished mark uses a new line, which makes all its curves in one go.
final class SmoothLine {
    private var curves = CGMutablePath()
    /// The number of points that `curves` has, and the first of them.
    private var count = 0
    private var first = CGPoint.zero

    /// The path through the points. A line with fewer than two points is empty.
    func path(through points: [CGPoint]) -> CGPath {
        guard points.count > 1 else { return CGMutablePath() }
        if points.count < count || points[0] != first {
            // A different line: start again.
            curves = CGMutablePath()
            count = 0
        }
        if count == 0 {
            first = points[0]
            curves.move(to: first)
        }
        // The curve at a point needs the point after it, so the last point has no curve yet.
        for index in max(count - 1, 1)..<(points.count - 1) {
            let next = points[index + 1]
            let middle = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
            curves.addQuadCurve(to: middle, control: points[index])
        }
        count = points.count
        // The last part is a straight line to the pointer. The next point replaces it with a curve.
        let path = curves.mutableCopy() ?? CGMutablePath()
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// The text system of one Text mark: the text, and the width where a line breaks.
///
/// The text field of the overlay and `MarkRenderer` both use this layout. Thus the lines of the
/// finished mark break at the same places as the lines that the user typed.
struct TextLayout {
    // The storage owns the manager, and the manager owns the container.
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer

    init(text: String, style: MarkStyle, wrapWidth: CGFloat) {
        storage = NSTextStorage(string: text, attributes: MarkRenderer.textAttributes(style))
        container = NSTextContainer(size: CGSize(width: max(wrapWidth, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    /// The area that the lines of the text use, from the top-left of the text.
    var usedRect: CGRect {
        _ = manager.glyphRange(for: container)
        return manager.usedRect(for: container)
    }
}
