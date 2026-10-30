import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let popoverWidth = Theme.Metrics.popoverWidth
    static let popoverHeight = Theme.Metrics.popoverHeight

    private var settings: Settings!
    private var engine: NoiseEngine!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var ballView: BallView!
    private var settingsWindow: SettingsWindow?
    private var tickTimer: Timer?
    private var iconContent: (state: PlayState, label: String)?
    private let speech = AVSpeechSynthesizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        settings = Settings()
        engine = NoiseEngine(settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        buildPopover()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.close()
    }

    private func buildPopover() {
        let w = Self.popoverWidth, h = Self.popoverHeight
        let container = PopoverContentView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        ballView = BallView(frame: NSRect(x: 0, y: 0, width: w, height: h), engine: engine, settings: settings)
        ballView.onRelease = { [weak self] seconds in self?.startNoise(seconds: seconds) }
        ballView.onToggle = { [weak self] in self?.togglePause() }
        container.addSubview(ballView)

        let side = Theme.Metrics.iconButton, inset = Theme.Metrics.iconInset
        let gear = IconButton(glyph: .settings, label: "Settings", target: self, action: #selector(openSettings(_:)))
        gear.frame.origin = NSPoint(x: w - inset - side, y: h - inset - side)
        container.addSubview(gear)

        let quit = IconButton(glyph: .close, label: "Quit noiser", target: self, action: #selector(quit(_:)))
        quit.frame.origin = NSPoint(x: inset, y: h - inset - side)
        container.addSubview(quit)

        let controller = NSViewController()
        controller.view = container
        popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: w, height: h)
        popover.behavior = .transient
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app isn't frontmost, so make the popover key to receive the drag.
        NSApp.activate()
    }

    private func startNoise(seconds: Double?) {
        engine.start(seconds: seconds)
        refresh()
    }

    private func togglePause() {
        switch engine.state {
        case .playing: engine.pause()
        case .paused: engine.resume()
        case .idle: engine.start(seconds: nil)
        }
        refresh()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func tick() {
        if engine.takeFinished() {
            ballView.showTimeIsUp()
            if settings.announce {
                speech.speak(AVSpeechUtterance(string: "time is up"))
            }
        }
        refresh()
    }

    private func refresh() {
        let state = engine.state
        setIcon(state, label: MenuBarIcon.label(state: state, remaining: engine.remaining()))
        ballView.needsDisplay = true
    }

    private func setIcon(_ state: PlayState, label: String) {
        guard iconContent?.state != state || iconContent?.label != label else { return }
        iconContent = (state, label)
        statusItem.button?.image = MenuBarIcon.image(for: state, label: label)
    }

    @objc private func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let panel = SettingsWindow(settings: settings)
            panel.onNoiseChanged = { [weak self] kind in self?.engine.setNoise(kind) }
            panel.onVolumeChanged = { [weak self] db in self?.engine.setVolumeDb(db) }
            panel.onColorChanged = { [weak self] in self?.ballView.needsDisplay = true }
            settingsWindow = panel
        }
        popover.performClose(nil)
        settingsWindow?.show()
    }
}
