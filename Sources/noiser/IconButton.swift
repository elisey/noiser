import AppKit

/// The ✕ and settings buttons of the popover: a glyph drawn in code, highlighted on hover.
final class IconButton: NSButton {
    enum Glyph { case close, settings }

    private let glyph: Glyph
    private var hovering = false

    init(glyph: Glyph, label: String, target: AnyObject?, action: Selector) {
        self.glyph = glyph
        let side = Theme.Metrics.iconButton
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        focusRingType = .none
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private var focused: Bool {
        window?.firstResponder === self && window?.isKeyWindow == true
    }

    /// Sizes below are from the design system's 24 pt button and scale with the popover.
    private func s(_ value: CGFloat) -> CGFloat { Theme.Metrics.popover(value) }

    override func draw(_ dirtyRect: NSRect) {
        let active = hovering || isHighlighted
        if active {
            Theme.paperDeep.setFill()
            let radius = s(8)
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        if focused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: s(1), dy: s(1)), xRadius: s(7), yRadius: s(7))
            ring.lineWidth = s(2)
            Theme.ink.setStroke()
            ring.stroke()
        }
        let color = active || focused ? Theme.ink : Theme.inkFaint
        // Glyphs are drawn on the SVG's 12×12 grid, scaled with the popover and centered in the button.
        let origin = NSPoint(x: bounds.midX - s(6), y: bounds.midY - s(6))
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + s(x), y: origin.y + s(y)) }

        color.set()
        let path = NSBezierPath()
        path.lineCapStyle = .round
        switch glyph {
        case .close:
            path.lineWidth = s(2.2)
            path.move(to: point(2.5, 2.5)); path.line(to: point(9.5, 9.5))
            path.move(to: point(9.5, 2.5)); path.line(to: point(2.5, 9.5))
            path.stroke()
        case .settings:
            path.lineWidth = s(2)
            path.move(to: point(1.5, 3.5)); path.line(to: point(10.5, 3.5))
            path.move(to: point(1.5, 8.5)); path.line(to: point(10.5, 8.5))
            path.stroke()
            for (x, y) in [(4.0, 3.5), (8.0, 8.5)] {
                let dot = point(x, y), r = s(2)
                NSBezierPath(ovalIn: NSRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)).fill()
            }
        }
    }
}
