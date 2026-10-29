import AppKit

/// The shared color panel remembers an arbitrary last position; open it next to our window.
final class AnchoredColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        guard let window else { return }
        let panel = NSColorPanel.shared
        let frame = window.frame
        let wanted = NSRect(
            x: frame.maxX + 8,
            y: frame.maxY - panel.frame.height,
            width: panel.frame.width,
            height: panel.frame.height
        )
        panel.setFrameOrigin(window.constrainFrameRect(wanted, to: window.screen).origin)
        panel.orderFront(nil)
    }
}

/// Closes on Escape; the window has no Close button.
final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// The small mark next to the window title: ink thread, ball-colored ball (noiser-mark.svg at 1/8).
final class TitleMarkView: NSView {
    var ballColor: NSColor = Theme.ball { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let scale = bounds.height / 120
        Theme.ink.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 29 * scale, y: 0, width: 22 * scale, height: 52 * scale),
            xRadius: 11 * scale, yRadius: 11 * scale
        ).fill()
        ballColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 40 * scale, width: 80 * scale, height: 80 * scale)).fill()
    }
}

/// Flipped so the layout reads top to bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let width = Theme.Metrics.settingsWidth
    static let margin: CGFloat = 24
    static let labelWidth: CGFloat = 76
    static let gap: CGFloat = 16
    static let rowGap: CGFloat = 24
    /// The content starts below at least this much title bar, whatever the system's own height.
    static let minTitlebarHeight: CGFloat = 32

    let window: NSWindow
    private let settings: Settings
    private let colorWell: AnchoredColorWell
    private let titleMark = TitleMarkView()
    private let volumeCell = VolumeSliderCell()
    private var swatches: [(preset: BallPreset?, button: SwatchButton)] = []

    var onNoiseChanged: ((NoiseKind) -> Void)?
    var onVolumeChanged: ((Double) -> Void)?
    var onColorChanged: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
        let w = Self.width
        let controlX = Self.margin + Self.labelWidth + Self.gap
        let controlWidth = w - controlX - Self.margin

        window = EscapableWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "noiser"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.paper
        window.isReleasedWhenClosed = false
        // The well is never seen: it only connects the color panel, and the "+" swatch opens it.
        colorWell = AnchoredColorWell(frame: .zero)
        super.init()
        window.delegate = self

        let content = FlippedView()
        window.contentView = content
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height

        // Title: mark + wordmark, centered in the title bar.
        let wordmark = NSTextField(labelWithAttributedString: Theme.windowTitle.string("noiser", color: Theme.ink))
        wordmark.sizeToFit()
        let markSize = NSSize(width: 10, height: 15), markGap: CGFloat = 6
        let titleWidth = markSize.width + markGap + wordmark.frame.width
        let titleX = ((w - titleWidth) / 2).rounded()
        titleMark.frame = NSRect(origin: NSPoint(x: titleX, y: ((titlebarHeight - markSize.height) / 2).rounded()), size: markSize)
        titleMark.ballColor = color(fromHex: settings.ballColor)
        wordmark.frame.origin = NSPoint(
            x: titleX + markSize.width + markGap,
            y: ((titlebarHeight - wordmark.frame.height) / 2).rounded()
        )
        content.addSubview(titleMark)
        content.addSubview(wordmark)

        var y = max(titlebarHeight, Self.minTitlebarHeight) + Self.margin

        func label(_ text: String, centerY: CGFloat) {
            let field = NSTextField(labelWithAttributedString: Theme.label.string(text, color: Theme.inkMuted))
            field.sizeToFit()
            // Right-aligned against the controls.
            field.frame.origin = NSPoint(
                x: Self.margin + Self.labelWidth - field.frame.width,
                y: (centerY - field.frame.height / 2).rounded()
            )
            content.addSubview(field)
        }

        // Noise
        let noise = SegmentedPill(titles: NoiseKind.allCases.map(\.title), selectedIndex: settings.noise.rawValue)
        noise.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 34)
        noise.target = self
        noise.action = #selector(noiseChanged(_:))
        noise.setAccessibilityLabel("Noise")
        content.addSubview(noise)
        label("Noise", centerY: noise.frame.midY)
        y = noise.frame.maxY + Self.rowGap

        // Volume: slider, then the scale under it.
        let knob = VolumeSliderCell.knobSize
        let slider = NSSlider(frame: NSRect(x: controlX - knob / 2, y: y, width: controlWidth + knob, height: knob))
        volumeCell.minValue = NoiseEngine.volumeMinDb
        volumeCell.maxValue = NoiseEngine.volumeMaxDb
        volumeCell.knobColor = color(fromHex: settings.ballColor)
        slider.cell = volumeCell
        slider.doubleValue = settings.volumeDb
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(volumeChanged(_:))
        slider.setAccessibilityLabel("Volume")
        content.addSubview(slider)

        let scaleTop = slider.frame.maxY + 4
        for (value, alignRight) in [(NoiseEngine.volumeMinDb, false), (NoiseEngine.volumeMaxDb, true)] {
            let field = NSTextField(labelWithAttributedString: Theme.caption.string(Self.decibels(value), color: Theme.inkMuted))
            field.sizeToFit()
            let x = alignRight ? controlX + controlWidth - field.frame.width : controlX
            field.frame.origin = NSPoint(x: x, y: scaleTop)
            content.addSubview(field)
        }
        let scaleBottom = scaleTop + 16
        label("Volume", centerY: ((y + scaleBottom) / 2).rounded())
        y = scaleBottom + Self.rowGap

        // Ball
        let outset = SwatchButton.outset, step: CGFloat = 36
        var x = controlX - outset
        for preset in BallPreset.allCases {
            let swatch = SwatchButton(kind: .color(preset.color), label: preset.title, target: self, action: #selector(presetChosen(_:)))
            swatch.frame.origin = NSPoint(x: x, y: y - outset)
            content.addSubview(swatch)
            swatches.append((preset, swatch))
            x += step
        }
        let custom = SwatchButton(kind: .custom(nil), label: "Custom color", target: self, action: #selector(customChosen(_:)))
        custom.frame.origin = NSPoint(x: x, y: y - outset)
        content.addSubview(custom)
        swatches.append((nil, custom))
        content.addSubview(colorWell)
        colorWell.color = color(fromHex: settings.ballColor)
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        label("Ball", centerY: y + SwatchButton.diameter / 2)
        y += SwatchButton.diameter + Self.rowGap

        // Announce
        let announce = InkCheckbox(title: "Announce “time is up”", target: self, action: #selector(announceChanged(_:)))
        announce.frame.origin = NSPoint(x: controlX, y: y)
        announce.state = settings.announce ? .on : .off
        content.addSubview(announce)
        y = announce.frame.maxY + Self.margin

        window.setContentSize(NSSize(width: w, height: y))
        window.center()
        updateSwatches()
    }

    /// "−30 DB", "+12 DB" (with a real minus sign).
    static func decibels(_ value: Double) -> String {
        let number = Int(value.rounded())
        let sign = number < 0 ? "\u{2212}" : number > 0 ? "+" : ""
        return "\(sign)\(abs(number)) dB"
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The shared color panel outlives the color well; take it down with the settings.
    func windowWillClose(_ notification: Notification) {
        colorWell.deactivate()
        NSColorPanel.shared.orderOut(nil)
    }

    private func updateSwatches() {
        let selected = BallPreset.matching(settings.ballColor)
        for (preset, button) in swatches {
            if let preset {
                button.isSelected = preset == selected
            } else {
                button.isSelected = selected == nil
                button.kind = .custom(selected == nil ? color(fromHex: settings.ballColor) : nil)
            }
        }
        let ball = color(fromHex: settings.ballColor)
        titleMark.ballColor = ball
        volumeCell.knobColor = ball
        volumeCell.controlView?.needsDisplay = true
    }

    private func setBallColor(_ hex: String?) {
        settings.ballColor = hex
        updateSwatches()
        onColorChanged?()
    }

    @objc private func noiseChanged(_ sender: SegmentedPill) {
        guard let kind = NoiseKind(rawValue: sender.selectedIndex) else { return }
        settings.noise = kind
        onNoiseChanged?(kind)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        settings.volumeDb = sender.doubleValue
        onVolumeChanged?(sender.doubleValue)
    }

    @objc private func presetChosen(_ sender: SwatchButton) {
        guard let preset = swatches.first(where: { $0.button === sender })?.preset else { return }
        colorWell.deactivate()
        setBallColor(preset.hex)
    }

    @objc private func customChosen(_ sender: SwatchButton) {
        colorWell.activate(true)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        setBallColor(hex(from: sender.color))
    }

    @objc private func announceChanged(_ sender: NSButton) {
        settings.announce = sender.state == .on
    }
}
