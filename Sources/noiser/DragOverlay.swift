import AppKit

final class OverlayView: NSView {
    var anchor = NSPoint.zero
    var ball = NSPoint.zero
    var color = NSColor.controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        drawBallOnString(anchor: anchor, center: ball, color: color)
    }
}

/// Transparent click-through windows, one per screen: the popover can't draw outside its
/// own bounds, and with "Displays have separate Spaces" a single window is clipped to
/// whichever display it belongs to.
final class DragOverlay {
    private struct Layer {
        let window: NSWindow
        let view: OverlayView
        let origin: NSPoint
    }

    private var layers: [Layer] = []
    private var screenFrames: [NSRect] = []

    private func build() {
        hide()
        layers = NSScreen.screens.map { screen in
            let frame = screen.frame
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            let view = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = view
            return Layer(window: window, view: view, origin: frame.origin)
        }
    }

    func show() {
        let frames = NSScreen.screens.map(\.frame)
        if frames != screenFrames {
            build()
            screenFrames = frames
        }
        for layer in layers { layer.window.orderFront(nil) }
    }

    func update(anchor: NSPoint, ball: NSPoint, color: NSColor) {
        for layer in layers {
            layer.view.anchor = NSPoint(x: anchor.x - layer.origin.x, y: anchor.y - layer.origin.y)
            layer.view.ball = NSPoint(x: ball.x - layer.origin.x, y: ball.y - layer.origin.y)
            layer.view.color = color
            layer.view.needsDisplay = true
        }
    }

    func hide() {
        for layer in layers { layer.window.orderOut(nil) }
    }
}
