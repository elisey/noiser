import AppKit

final class BallView: NSView {
    static let ballTop: CGFloat = 26
    static let textTop: CGFloat = 62

    let engine: NoiseEngine
    let settings: Settings
    /// Ball released: seconds, or nil for no timer.
    var onRelease: ((Double?) -> Void)?
    /// Click on the panel outside the ball.
    var onToggle: (() -> Void)?

    private var dragging = false
    private var windowPress = false
    private var returning = false
    private var grabPoint = NSPoint.zero  // screen coords at mouseDown
    private var delta = NSPoint.zero  // ball displacement from rest, screen coords (y up)
    private lazy var overlay = DragOverlay()
    private var returnTimer: Timer?

    init(frame: NSRect, engine: NoiseEngine, settings: Settings) {
        self.engine = engine
        self.settings = settings
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var restCenter: NSPoint {
        NSPoint(x: bounds.width / 2, y: Self.ballTop)
    }

    private func toScreen(_ point: NSPoint) -> NSPoint {
        window?.convertPoint(toScreen: convert(point, to: nil)) ?? point
    }

    private var dragDistance: Double {
        hypot(delta.x, delta.y)
    }

    private func labels() -> (main: String, sub: String) {
        if dragging {
            let minutes = Duration.dragMinutes(points: dragDistance)
            if minutes < Duration.minMinutes {
                return ("∞", "release — no timer")
            }
            return (Duration.minutes(minutes), "release — start")
        }
        switch engine.state {
        case .idle:
            return ("", "drag or click")
        case .playing, .paused:
            let main = engine.remaining().map(Duration.hms) ?? "∞"
            return (main, engine.state == .paused ? "paused" : "playing")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rest = restCenter
        // While stretched, the ball is drawn on the overlay instead.
        if !(dragging || returning) {
            drawBallOnString(anchor: NSPoint(x: rest.x, y: 0), center: rest, color: color(fromHex: settings.ballColor))
        }

        let (main, sub) = labels()
        let top = Self.textTop
        drawCentered(
            main,
            in: NSRect(x: 0, y: top, width: bounds.width, height: 32),
            font: .monospacedDigitSystemFont(ofSize: 24, weight: .medium),
            color: .labelColor
        )
        drawCentered(
            sub,
            in: NSRect(x: 0, y: top + 36, width: bounds.width, height: 18),
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
    }

    private func hitsBall(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let rest = restCenter
        let reach = ballRadius * 1.6
        return (p.x - rest.x) * (p.x - rest.x) + (p.y - rest.y) * (p.y - rest.y) <= reach * reach
    }

    override func mouseDown(with event: NSEvent) {
        if dragging { return }
        // The ball sets the timer; the rest of the popover is a play/pause button.
        guard hitsBall(event) else {
            windowPress = true
            return
        }
        stopReturn()
        returning = false
        dragging = true
        // Screen coordinates keep counting after the cursor leaves the popover.
        grabPoint = NSEvent.mouseLocation
        delta = .zero
        overlay.show()
        updateOverlay()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let m = NSEvent.mouseLocation
        delta = NSPoint(x: m.x - grabPoint.x, y: m.y - grabPoint.y)
        updateOverlay()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if windowPress {
            windowPress = false
            onToggle?()
            return
        }
        guard dragging else { return }
        dragging = false
        let minutes = Duration.dragMinutes(points: dragDistance)
        onRelease?(minutes >= Duration.minMinutes ? Double(minutes * 60) : nil)
        returning = true
        startReturn()
    }

    private func updateOverlay() {
        let rest = restCenter
        let restScreen = toScreen(rest)
        let ball = NSPoint(x: restScreen.x + delta.x, y: restScreen.y + delta.y)
        overlay.update(
            anchor: toScreen(NSPoint(x: rest.x, y: 0)),
            ball: ball,
            color: color(fromHex: settings.ballColor)
        )
    }

    private func startReturn() {
        stopReturn()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.returnStep() }
        RunLoop.main.add(timer, forMode: .common)
        returnTimer = timer
    }

    private func stopReturn() {
        returnTimer?.invalidate()
        returnTimer = nil
    }

    private func returnStep() {
        delta = NSPoint(x: delta.x * 0.6, y: delta.y * 0.6)
        if dragDistance < 0.5 {
            delta = .zero
            returning = false
            stopReturn()
            overlay.hide()
        } else {
            updateOverlay()
        }
        needsDisplay = true
    }
}
