import AppKit

/// Ball color presets of the settings window. Settings stores them as "#RRGGBB"; nil is the default ball.
enum BallPreset: CaseIterable {
    case tomato, violet, ink

    /// Ink follows the appearance (black on light paper, cream on dark), so its stored value
    /// stands for the token rather than a fixed color.
    static let inkHex = "#121212"

    var hex: String? {
        switch self {
        case .tomato: return nil
        case .violet: return "#5A3CF0"
        case .ink: return Self.inkHex
        }
    }

    var color: NSColor {
        switch self {
        case .tomato: return Theme.ball
        case .violet: return Theme.violet
        case .ink: return Theme.ink
        }
    }

    var title: String {
        switch self {
        case .tomato: return "Tomato"
        case .violet: return "Violet"
        case .ink: return "Ink"
        }
    }

    /// nil for a custom color.
    static func matching(_ hex: String?) -> BallPreset? {
        allCases.first { $0.hex == hex }
    }
}

private func drawFocusRing(_ path: NSBezierPath) {
    path.lineWidth = 2
    Theme.ink.setStroke()
    path.stroke()
}

// MARK: - Noise segments

/// Pill-shaped segmented control. Accessible as a radio group; arrow keys move the selection.
final class SegmentedPill: NSControl {
    let titles: [String]
    private(set) var selectedIndex: Int
    private var segmentElements: [SegmentElement] = []

    static let font = Theme.TextStyle(size: 12, weight: 800)
    private let inset: CGFloat = 4

    init(titles: [String], selectedIndex: Int) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        super.init(frame: .zero)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func segmentFrame(_ index: Int) -> NSRect {
        let inner = bounds.insetBy(dx: inset, dy: inset)
        let width = inner.width / CGFloat(titles.count)
        return NSRect(x: inner.minX + CGFloat(index) * width, y: inner.minY, width: width, height: inner.height)
    }

    func select(_ index: Int, sendAction: Bool) {
        guard titles.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
        if sendAction { self.sendAction(action, to: target) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let index = titles.indices.first(where: { segmentFrame($0).contains(p) }) {
            select(index, sendAction: true)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: select(selectedIndex - 1, sendAction: true)
        case .rightArrow?: select(selectedIndex + 1, sendAction: true)
        default: super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        Theme.paperDeep.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        for (index, title) in titles.enumerated() {
            let frame = segmentFrame(index)
            let selected = index == selectedIndex
            if selected {
                Theme.ink.setFill()
                NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
            }
            let text = Self.font.string(title, color: selected ? Theme.onInk : Theme.ink)
            drawCentered(text, top: frame.minY, lineHeight: frame.height, in: frame)
        }

        if window?.firstResponder === self, window?.isKeyWindow == true {
            let ring = bounds.insetBy(dx: 1, dy: 1)
            drawFocusRing(NSBezierPath(roundedRect: ring, xRadius: ring.height / 2, yRadius: ring.height / 2))
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }

    override func accessibilityChildren() -> [Any]? {
        if segmentElements.count != titles.count {
            segmentElements = titles.indices.map { SegmentElement(control: self, index: $0) }
        }
        return segmentElements
    }

    override func accessibilityValue() -> Any? {
        titles.indices.contains(selectedIndex) ? titles[selectedIndex] : nil
    }

    private final class SegmentElement: NSAccessibilityElement {
        weak var control: SegmentedPill?
        let index: Int

        init(control: SegmentedPill, index: Int) {
            self.control = control
            self.index = index
            super.init()
            setAccessibilityRole(.radioButton)
            setAccessibilityLabel(control.titles[index])
            setAccessibilityParent(control)
        }

        override func accessibilityFrame() -> NSRect {
            guard let control, let window = control.window else { return .zero }
            let rect = control.convert(control.segmentFrame(index), to: nil)
            return window.convertToScreen(rect)
        }

        override func accessibilityValue() -> Any? {
            NSNumber(value: control?.selectedIndex == index)
        }

        override func accessibilityPerformPress() -> Bool {
            control?.select(index, sendAction: true)
            return true
        }
    }
}

// MARK: - Volume slider

/// Thick track with the played part in ink and a knob in the ball color. The knob's center
/// travels the whole track, so the control is wider than the track by half a knob on each side.
final class VolumeSliderCell: NSSliderCell {
    static let knobSize: CGFloat = 24
    static let trackHeight: CGFloat = 6
    var knobColor: NSColor = Theme.ball

    override var knobThickness: CGFloat { Self.knobSize }

    private var fraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((doubleValue - minValue) / (maxValue - minValue))
    }

    func trackRect(in bounds: NSRect) -> NSRect {
        let inset = Self.knobSize / 2
        return NSRect(x: bounds.minX + inset, y: bounds.midY - Self.trackHeight / 2,
                      width: bounds.width - 2 * inset, height: Self.trackHeight)
    }

    override func barRect(flipped: Bool) -> NSRect {
        trackRect(in: controlView?.bounds ?? .zero)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let track = barRect(flipped: flipped)
        let x = track.minX + fraction * track.width
        return NSRect(x: x - Self.knobSize / 2, y: track.midY - Self.knobSize / 2, width: Self.knobSize, height: Self.knobSize)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = barRect(flipped: flipped)
        let radius = track.height / 2
        Theme.hairline.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        var played = track
        played.size.width = fraction * track.width
        Theme.ink.setFill()
        NSBezierPath(roundedRect: played, xRadius: radius, yRadius: radius).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        knobColor.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSBezierPath(ovalIn: knobRect(flipped: controlView.isFlipped)).fill()
    }

    override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect {
        knobRect(flipped: controlView.isFlipped)
    }
}

// MARK: - Ball swatches

/// A 26pt color circle; selected swatches get a double ring (paper, then ink).
final class SwatchButton: NSButton {
    enum Kind {
        case color(NSColor)
        /// Opens the color panel; filled with the custom color when one is in use.
        case custom(NSColor?)
    }

    static let diameter: CGFloat = 26
    /// Room for the selection rings around the circle.
    static let outset: CGFloat = 5

    var kind: Kind { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }

    init(kind: Kind, label: String, target: AnyObject?, action: Selector) {
        self.kind = kind
        let side = Self.diameter + 2 * Self.outset
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

    override func accessibilityValue() -> Any? {
        NSNumber(value: isSelected)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: Self.outset, dy: Self.outset)
        let focused = window?.firstResponder === self && window?.isKeyWindow == true

        if isSelected || focused {
            // Ink ring 2pt outside a 3pt paper gap.
            drawFocusRing(NSBezierPath(ovalIn: circle.insetBy(dx: -4, dy: -4)))
        }
        switch kind {
        case .color(let color):
            color.setFill()
            NSBezierPath(ovalIn: circle).fill()
        case .custom(let color?):
            color.setFill()
            NSBezierPath(ovalIn: circle).fill()
        case .custom(nil):
            let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            Theme.inkFaint.setStroke()
            ring.stroke()
            let plus = NSBezierPath()
            let c = NSPoint(x: circle.midX, y: circle.midY), arm: CGFloat = 5
            plus.move(to: NSPoint(x: c.x - arm, y: c.y)); plus.line(to: NSPoint(x: c.x + arm, y: c.y))
            plus.move(to: NSPoint(x: c.x, y: c.y - arm)); plus.line(to: NSPoint(x: c.x, y: c.y + arm))
            plus.lineWidth = 2
            plus.lineCapStyle = .round
            plus.stroke()
        }
    }
}

// MARK: - Checkbox

/// 20pt rounded square, ink when checked, with the title in the label style.
final class InkCheckbox: NSButton {
    static let side: CGFloat = 20
    static let gap: CGFloat = 10

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        self.target = target
        self.action = action
        focusRingType = .none
        let titleWidth = Theme.label.string(title, color: Theme.ink).size().width.rounded(.up)
        frame.size = NSSize(width: Self.side + Self.gap + titleWidth, height: Self.side)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0, y: (bounds.height - Self.side) / 2, width: Self.side, height: Self.side)
        if state == .on {
            Theme.ink.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: box.minX + 6, y: box.midY + 0.5))
            check.line(to: NSPoint(x: box.minX + 8.75, y: box.midY + 3.25))
            check.line(to: NSPoint(x: box.minX + 14, y: box.midY - 2.75))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            Theme.onInk.setStroke()
            check.stroke()
        } else {
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            outline.lineWidth = 2
            Theme.inkFaint.setStroke()
            outline.stroke()
        }
        if window?.firstResponder === self, window?.isKeyWindow == true {
            drawFocusRing(NSBezierPath(roundedRect: box.insetBy(dx: -3, dy: -3), xRadius: 8, yRadius: 8))
        }
        let text = Theme.label.string(title, color: Theme.ink)
        let textFrame = NSRect(x: Self.side + Self.gap, y: 0, width: text.size().width, height: bounds.height)
        drawCentered(text, top: 0, lineHeight: bounds.height, in: textFrame)
    }
}
