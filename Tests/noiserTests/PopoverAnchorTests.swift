import AppKit
import Testing
@testable import noiser

@MainActor struct PopoverAnchorTests {
    @Test func coversTheGivenFrameAndStaysClickThrough() {
        let anchor = PopoverAnchor()
        let frame = NSRect(x: 1200, y: 870, width: 44, height: 24)
        let view = anchor.place(at: frame)
        #expect(anchor.window.frame == frame)
        #expect(view.window === anchor.window)
        #expect(view.bounds.size == frame.size)
        #expect(anchor.window.ignoresMouseEvents)
        #expect(!anchor.window.isOpaque)
        anchor.hide()
        #expect(!anchor.window.isVisible)
    }

    @Test func movingTheAnchorKeepsTheSameView() {
        let anchor = PopoverAnchor()
        let first = anchor.place(at: NSRect(x: 0, y: 0, width: 30, height: 24))
        let second = anchor.place(at: NSRect(x: 100, y: 0, width: 60, height: 24))
        #expect(first === second)
        #expect(anchor.window.frame.width == 60)
        anchor.hide()
    }
}
