import AppKit

let ballRadius: CGFloat = 14

func color(fromHex value: String?) -> NSColor {
    guard let value, value.count == 7, let rgb = UInt32(value.dropFirst(), radix: 16) else {
        return .controlAccentColor
    }
    return NSColor(
        srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: 1
    )
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

func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style,
    ]).draw(in: rect)
}

func drawBallOnString(anchor: NSPoint, center: NSPoint, color: NSColor) {
    NSColor.secondaryLabelColor.setStroke()
    let string = NSBezierPath()
    string.move(to: anchor)
    string.line(to: center)
    string.lineWidth = 1.5
    string.stroke()

    color.setFill()
    let ball = NSRect(x: center.x - ballRadius, y: center.y - ballRadius, width: 2 * ballRadius, height: 2 * ballRadius)
    NSBezierPath(ovalIn: ball).fill()
}

func symbolImage(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    image?.isTemplate = true
    return image
}
