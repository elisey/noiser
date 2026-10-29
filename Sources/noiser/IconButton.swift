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

    override func draw(_ dirtyRect: NSRect) {
        let active = hovering || isHighlighted
        if active {
            Theme.paperDeep.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        if focused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            ring.lineWidth = 2
            Theme.ink.setStroke()
            ring.stroke()
        }
        let color = active || focused ? Theme.ink : Theme.inkFaint
        // Glyphs are drawn on a 12×12 grid centered in the button.
        let origin = NSPoint(x: bounds.midX - 6, y: bounds.midY - 6)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x, y: origin.y + y) }

        color.set()
        let path = NSBezierPath()
        path.lineCapStyle = .round
        switch glyph {
        case .close:
            path.lineWidth = 2.2
            path.move(to: point(2.5, 2.5)); path.line(to: point(9.5, 9.5))
            path.move(to: point(9.5, 2.5)); path.line(to: point(2.5, 9.5))
            path.stroke()
        case .settings:
            path.lineWidth = 2
            path.move(to: point(1.5, 3.5)); path.line(to: point(10.5, 3.5))
            path.move(to: point(1.5, 8.5)); path.line(to: point(10.5, 8.5))
            path.stroke()
            for (x, y) in [(4.0, 3.5), (8.0, 8.5)] {
                NSBezierPath(ovalIn: NSRect(x: origin.x + x - 2, y: origin.y + y - 2, width: 4, height: 4)).fill()
            }
        }
    }
}
