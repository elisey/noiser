import AppKit

/// What the popover shows for a given state.
struct PopoverDisplay: Equatable {
    enum TimeTone { case faint, ink }

    let time: String
    let timeTone: TimeTone
    let longTime: Bool
    let pill: String
    let pillLook: PillLook
    let ball: BallLook
    /// While dragging the resting place shows a dashed outline; the ball itself is on the overlay.
    let ghost: Bool

    /// `dragMinutes` is non-nil while the ball is being dragged.
    static func make(state: PlayState, remaining: Double?, dragMinutes: Int?, timeIsUp: Bool) -> PopoverDisplay {
        if let minutes = dragMinutes {
            if minutes < Duration.minMinutes {
                return PopoverDisplay(time: "∞", timeTone: .ink, longTime: false,
                                      pill: "release — no timer", pillLook: .lime, ball: .solid, ghost: true)
            }
            return PopoverDisplay(time: Duration.minutes(minutes), timeTone: .ink, longTime: false,
                                  pill: "release — start", pillLook: .lime, ball: .solid, ghost: true)
        }
        switch state {
        case .idle:
            if timeIsUp {
                return PopoverDisplay(time: "00:00", timeTone: .ink, longTime: false,
                                      pill: "time is up", pillLook: .tomato, ball: .solid, ghost: false)
            }
            return PopoverDisplay(time: "00:00", timeTone: .faint, longTime: false,
                                  pill: "drag or click", pillLook: .outline, ball: .solid, ghost: false)
        case .playing, .paused:
            let time = remaining.map(Duration.hms) ?? "∞"
            let paused = state == .paused
            return PopoverDisplay(time: time, timeTone: .ink, longTime: Int(remaining ?? 0) >= 3600,
                                  pill: paused ? "paused" : "playing", pillLook: paused ? .outline : .ink,
                                  ball: paused ? .ring : .solid, ghost: false)
        }
    }
}

final class BallView: NSView {
    static let timeUpSeconds = 3.0
    static let hoverScale: CGFloat = 1.06

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
    private var hovering = false
    private var timeUpUntil: Date?

    init(frame: NSRect, engine: NoiseEngine, settings: Settings) {
        self.engine = engine
        self.settings = settings
        super.init(frame: frame)
        // The thread's round cap reaches above the top edge; clipping cuts it flat there.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var restCenter: NSPoint {
        NSPoint(x: bounds.width / 2, y: Theme.Metrics.ballTop + ballRadius)
    }

    /// Shows "time is up" until a few seconds pass or the next click.
    func showTimeIsUp() {
        timeUpUntil = Date().addingTimeInterval(Self.timeUpSeconds)
        needsDisplay = true
    }

    private var timeIsUp: Bool {
        guard let until = timeUpUntil else { return false }
        if Date() < until { return true }
        timeUpUntil = nil
        return false
    }

    private func toScreen(_ point: NSPoint) -> NSPoint {
        window?.convertPoint(toScreen: convert(point, to: nil)) ?? point
    }

    private var dragDistance: Double {
        hypot(delta.x, delta.y)
    }

    private func currentDisplay() -> PopoverDisplay {
        PopoverDisplay.make(
            state: engine.state,
            remaining: engine.remaining(),
            dragMinutes: dragging ? Duration.dragMinutes(points: dragDistance) : nil,
            timeIsUp: timeIsUp
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let display = currentDisplay()
        let rest = restCenter
        if display.ghost {
            drawBallGhost(center: rest)
        } else if !returning {
            // While springing back, the ball is still drawn on the overlay.
            drawBallOnString(
                anchor: NSPoint(x: rest.x, y: 0),
                center: rest,
                color: color(fromHex: settings.ballColor),
                look: display.ball,
                scale: hovering ? Self.hoverScale : 1
            )
        }

        let style = display.longTime ? Theme.timeLong : Theme.time
        let timeColor = display.timeTone == .faint ? Theme.inkFaint : Theme.ink
        drawCentered(style.string(display.time, color: timeColor), top: Theme.Metrics.timeTop, lineHeight: 46, in: bounds)
        drawPill(display.pill, look: display.pillLook, top: Theme.Metrics.pillTop, in: bounds)
    }

    // MARK: Hover and cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(hitsBall(event))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(false)
    }

    private func updateHover(_ over: Bool) {
        guard !dragging else { return }
        if over { NSCursor.openHand.set() } else if hovering { NSCursor.arrow.set() }
        if over != hovering {
            hovering = over
            needsDisplay = true
        }
    }

    private func hitsBall(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let rest = restCenter
        let reach = ballRadius * 1.6
        return (p.x - rest.x) * (p.x - rest.x) + (p.y - rest.y) * (p.y - rest.y) <= reach * reach
    }

    override func mouseDown(with event: NSEvent) {
        if dragging { return }
        timeUpUntil = nil
        // The ball sets the timer; the rest of the popover is a play/pause button.
        guard hitsBall(event) else {
            windowPress = true
            return
        }
        stopReturn()
        returning = false
        dragging = true
        hovering = false
        NSCursor.closedHand.set()
        // Screen coordinates keep counting after the cursor leaves the popover.
        grabPoint = NSEvent.mouseLocation
        delta = .zero
        overlay.show()
        updateOverlay()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        NSCursor.closedHand.set()
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
        updateHover(hitsBall(event))
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
