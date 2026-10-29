import AppKit

let ballRadius: CGFloat = Theme.Metrics.ballDiameter / 2

/// nil or a malformed value means the default ball color; the ink preset follows the appearance.
func color(fromHex value: String?) -> NSColor {
    if value == BallPreset.inkHex { return Theme.ink }
    guard let value, value.count == 7, value.hasPrefix("#"), let rgb = UInt32(value.dropFirst(), radix: 16) else {
        return Theme.ball
    }
    return Theme.rgb(rgb)
}

func hex(from color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    return String(
        format: "#%02X%02X%02X",
        Int((c.redComponent * 255).rounded()),
        Int((c.greenComponent * 255).rounded()),
        Int((c.blueComponent * 255).rounded())
    )
}

/// Draws one line of styled text centered horizontally in `rect`, with the glyphs centered
/// vertically in a line box of `lineHeight` starting at `top` (CSS line-height semantics).
/// Expects a flipped view.
func drawCentered(_ text: NSAttributedString, top: CGFloat, lineHeight: CGFloat, in rect: NSRect) {
    let size = text.size()
    let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let ascent = font?.ascender ?? size.height
    let descent = -(font?.descender ?? 0)
    let baseline = top + (lineHeight - ascent - descent) / 2 + ascent
    let origin = NSPoint(x: rect.midX - size.width / 2, y: baseline - ascent)
    text.draw(with: NSRect(origin: origin, size: NSSize(width: size.width, height: ascent + descent)),
              options: [.usesLineFragmentOrigin])
}

enum BallLook {
    case solid
    /// Paused: a ring filled with paper.
    case ring
}

func drawBallOnString(anchor: NSPoint, center: NSPoint, color: NSColor, look: BallLook = .solid, scale: CGFloat = 1) {
    Theme.ink.setStroke()
    let thread = NSBezierPath()
    thread.move(to: anchor)
    thread.line(to: center)
    thread.lineWidth = Theme.Metrics.threadWidth
    thread.lineCapStyle = .round
    thread.stroke()

    drawBall(center: center, color: color, look: look, scale: scale)
}

func drawBall(center: NSPoint, color: NSColor, look: BallLook, scale: CGFloat = 1) {
    let radius = ballRadius * scale
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    switch look {
    case .solid:
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    case .ring:
        let ringWidth = Theme.Metrics.popover(9)
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
        ring.lineWidth = ringWidth
        Theme.paper.setFill()
        ring.fill()
        color.setStroke()
        ring.stroke()
    }
}

/// Where the ball rests while it is being dragged: a dashed outline.
func drawBallGhost(center: NSPoint) {
    let lineWidth = Theme.Metrics.popover(3)
    let rect = NSRect(x: center.x - ballRadius, y: center.y - ballRadius, width: 2 * ballRadius, height: 2 * ballRadius)
    let ghost = NSBezierPath(ovalIn: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
    ghost.lineWidth = lineWidth
    ghost.setLineDash([Theme.Metrics.popover(6), Theme.Metrics.popover(5)], count: 2, phase: 0)
    Theme.ink.withAlphaComponent(0.35).setStroke()
    ghost.stroke()
}

enum PillLook {
    case outline, ink, lime, tomato
}

/// Status pill centered horizontally in `rect`, top edge at `top`. Expects a flipped view.
func drawPill(_ text: String, look: PillLook, top: CGFloat, in rect: NSRect) {
    let textColor: NSColor
    switch look {
    case .outline: textColor = Theme.ink
    case .ink: textColor = Theme.onInk
    case .lime, .tomato: textColor = Theme.coal
    }
    let label = Theme.pill.string(text, color: textColor)
    let height = Theme.Metrics.pillHeight
    let padding = Theme.Metrics.popover(12)
    let width = (label.size().width + 2 * padding).rounded()
    let frame = NSRect(x: (rect.midX - width / 2).rounded(), y: top, width: width, height: height)

    switch look {
    case .outline:
        let lineWidth = Theme.Metrics.popover(1.5)
        let inset = frame.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: inset.height / 2, yRadius: inset.height / 2)
        path.lineWidth = lineWidth
        Theme.ink.setStroke()
        path.stroke()
    case .ink, .lime, .tomato:
        let fill: NSColor = look == .ink ? Theme.ink : look == .lime ? Theme.lime : Theme.tomato
        fill.setFill()
        NSBezierPath(roundedRect: frame, xRadius: height / 2, yRadius: height / 2).fill()
    }
    drawCentered(label, top: top, lineHeight: height, in: frame)
}
