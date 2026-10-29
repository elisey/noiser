import AppKit

/// Paints the whole popover frame, arrow included, with the paper color. NSPopover has no
/// background color of its own, so a view is slipped under the content into the popover's
/// frame view, which clips it to the popover shape.
final class PopoverContentView: NSView {
    private var background: PopoverBackgroundView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard background == nil, let frameView = window?.contentView?.superview else { return }
        let view = PopoverBackgroundView(frame: frameView.bounds)
        view.autoresizingMask = [.width, .height]
        frameView.addSubview(view, positioned: .below, relativeTo: nil)
        background = view
    }
}

private final class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill()
        dirtyRect.fill()
    }
}
