import AppKit

/// An invisible, click-through window that holds a fixed spot on screen for the popover to
/// point at, so the popover stays put when the status item changes width under it.
final class PopoverAnchor {
    let window: NSWindow

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
    }

    /// Moves the anchor over `screenFrame` and returns the view to show the popover from.
    func place(at screenFrame: NSRect) -> NSView {
        window.setFrame(screenFrame, display: false)
        window.orderFront(nil)
        return window.contentView!
    }

    func hide() {
        window.orderOut(nil)
    }
}
