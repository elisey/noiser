import AppKit

/// The status item: the ball-on-a-thread mark followed by the minutes left, drawn together
/// into one template image of constant width. The popover hangs off the status item, so a
/// status item that changed width would drag the popover sideways.
enum MenuBarIcon {
    static let markSize = NSSize(width: 18, height: 18)
    static let gap: CGFloat = 4
    /// The widest label the status item makes room for; tabular figures keep every number this wide.
    static let widestLabel = "00m"
    static let infinity = "∞"
    /// Archivo's ∞ is about the size of a lowercase "o"; drawn larger it reads next to the figures.
    static let infinityScale: CGFloat = 2
    /// Horizontal stretch of the ∞; the font is already at its widest.
    static let infinityStretch: CGFloat = 1.3
    /// Pulls the ∞ from the middle of the label's slot toward the mark.
    static let infinityShift: CGFloat = 3

    /// "24m", "<1m" in the last minute, whole hours and more (">2h") past 99 minutes,
    /// "∞" without a timer, "0m" when idle.
    static func label(state: PlayState, remaining: Double?) -> String {
        if state == .idle { return "0m" }
        guard let remaining else { return infinity }
        let minutes = Int(max(0, remaining) / 60)
        if minutes < 1 { return "<1m" }
        if minutes > 99 { return ">\(minutes / 60)h" }
        return "\(minutes)m"
    }

    static var size: NSSize {
        let textWidth = text(widestLabel).size().width.rounded(.up)
        return NSSize(width: markSize.width + gap + textWidth, height: markSize.height)
    }

    /// Mark and label as one template image; the label is left-aligned after the mark.
    static func image(for state: PlayState, label: String) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in
            drawMark(state)
            drawLabel(label, x: markSize.width + gap, slotWidth: bounds.width - markSize.width - gap, height: bounds.height)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "noiser, \(label)"
        return image
    }

    /// The mark alone on its 18×18 grid.
    static func markImage(for state: PlayState) -> NSImage {
        let image = NSImage(size: markSize, flipped: true) { _ in
            drawMark(state)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the mark on an 18×18 grid in a flipped context (see docs/redesign/assets/menubar-*.svg).
    private static func drawMark(_ state: PlayState) {
        NSColor.black.set()
        let center = NSPoint(x: 9, y: 11.75)
        let threadLength: CGFloat = state == .playing ? 7.5 : 6.5
        NSBezierPath(roundedRect: NSRect(x: 7.5, y: 0.5, width: 3, height: threadLength), xRadius: 1.5, yRadius: 1.5).fill()

        if state == .playing {
            let r: CGFloat = 5.5
            NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
            return
        }
        let r: CGFloat = 4.55
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ring.lineWidth = 1.9
        ring.stroke()
        if state == .paused {
            // Left half of the ball, covering the ring's outer edge.
            let half = NSBezierPath()
            half.appendArc(withCenter: center, radius: 5.5, startAngle: 90, endAngle: 270)
            half.close()
            half.fill()
        }
    }

    /// Black text: the image is a template, so the menu bar picks the real color.
    private static func text(_ label: String) -> NSAttributedString {
        Theme.menubar.string(label, color: .black)
    }

    /// Draws the label left-aligned at `x`, its line centered in `height` (flipped context).
    /// The enlarged ∞ sits near the middle of the label's slot and on the middle of the figures,
    /// instead of sharing their baseline.
    private static func drawLabel(_ label: String, x: CGFloat, slotWidth: CGFloat, height: CGFloat) {
        let font = Theme.menubar.font
        let baseline = (height - font.ascender + font.descender) / 2 + font.ascender
        guard label == infinity else {
            text(label).draw(with: NSRect(x: x, y: baseline - font.ascender, width: 100, height: height),
                             options: [.usesLineFragmentOrigin])
            return
        }
        let figuresMiddle = baseline - font.capHeight / 2
        let large = Theme.TextStyle(size: Theme.menubar.size * infinityScale, weight: Theme.menubar.weight)
        let string = large.string(label, color: .black)
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(string), nil)
        // Ink is measured upward from the baseline; lift the baseline so the ink's middle sits on the figures'.
        let infinityBaseline = figuresMiddle + ink.midY
        let lineHeight = large.font.ascender - large.font.descender
        let inkX = x + (slotWidth - ink.width * infinityStretch) / 2 - infinityShift
        // Stretched around the ink's left edge, so the glyph grows to the right from inkX.
        NSGraphicsContext.saveGraphicsState()
        let stretch = NSAffineTransform()
        stretch.translateX(by: inkX, yBy: 0)
        stretch.scaleX(by: infinityStretch, yBy: 1)
        stretch.concat()
        string.draw(with: NSRect(x: -ink.minX, y: infinityBaseline - large.font.ascender, width: 100, height: lineHeight),
                    options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }
}
