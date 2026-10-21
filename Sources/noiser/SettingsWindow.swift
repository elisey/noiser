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

final class SettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let settings: Settings
    private let colorWell: AnchoredColorWell

    var onNoiseChanged: ((NoiseKind) -> Void)?
    var onVolumeChanged: ((Double) -> Void)?
    var onColorChanged: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
        let w: CGFloat = 340, h: CGFloat = 230
        let margin: CGFloat = 20, labelWidth: CGFloat = 90, gap: CGFloat = 12
        let controlX = margin + labelWidth + gap
        let controlWidth = w - controlX - margin

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "noiser"
        window.isReleasedWhenClosed = false
        window.center()
        colorWell = AnchoredColorWell(frame: NSRect(x: 0, y: 0, width: 56, height: 26))
        super.init()
        window.delegate = self
        guard let content = window.contentView else { return }

        func row(_ text: String, centerY: CGFloat, control: NSView, height: CGFloat) {
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            label.frame = NSRect(x: margin, y: centerY - 9, width: labelWidth, height: 18)
            content.addSubview(label)
            let width = control.frame.width > 0 ? control.frame.width : controlWidth
            control.frame = NSRect(x: controlX, y: centerY - height / 2, width: width, height: height)
            content.addSubview(control)
        }

        let noisePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 26), pullsDown: false)
        for kind in NoiseKind.allCases {
            noisePopup.addItem(withTitle: kind.title)
            noisePopup.lastItem?.tag = kind.rawValue
        }
        noisePopup.selectItem(withTag: settings.noise.rawValue)
        noisePopup.target = self
        noisePopup.action = #selector(noiseChanged(_:))
        row("Noise", centerY: 188, control: noisePopup, height: 26)

        let volumeSlider = NSSlider(
            value: settings.volumeDb,
            minValue: NoiseEngine.volumeMinDb,
            maxValue: NoiseEngine.volumeMaxDb,
            target: self,
            action: #selector(volumeChanged(_:))
        )
        volumeSlider.isContinuous = true
        volumeSlider.frame = NSRect(x: 0, y: 0, width: controlWidth, height: 24)
        row("Volume", centerY: 148, control: volumeSlider, height: 24)

        colorWell.color = color(fromHex: settings.ballColor)
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        row("Ball", centerY: 108, control: colorWell, height: 26)

        let announce = NSButton(checkboxWithTitle: "Announce “time is up”", target: self, action: #selector(announceChanged(_:)))
        announce.frame = NSRect(x: controlX - 2, y: 66 - 11, width: controlWidth, height: 22)
        announce.state = settings.announce ? .on : .off
        content.addSubview(announce)

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow(_:)))
        close.frame = NSRect(x: w - margin - 96, y: 14, width: 96, height: 30)
        // Escape triggers the button, so the window also closes from the keyboard.
        close.keyEquivalent = "\u{1b}"
        content.addSubview(close)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func closeWindow(_ sender: Any?) {
        window.performClose(nil)
    }

    /// The shared color panel outlives the color well; take it down with the settings.
    func windowWillClose(_ notification: Notification) {
        colorWell.deactivate()
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func noiseChanged(_ sender: NSPopUpButton) {
        guard let kind = NoiseKind(rawValue: sender.selectedTag()) else { return }
        settings.noise = kind
        onNoiseChanged?(kind)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        settings.volumeDb = sender.doubleValue
        onVolumeChanged?(sender.doubleValue)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        settings.ballColor = hex(from: sender.color)
        onColorChanged?()
    }

    @objc private func announceChanged(_ sender: NSButton) {
        settings.announce = sender.state == .on
    }
}
