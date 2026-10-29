import AppKit
import Testing
@testable import noiser

struct MenuBarIconTests {
    @Test func minutesLabel() {
        #expect(MenuBarIcon.minutesLabel(remaining: nil) == nil)
        #expect(MenuBarIcon.minutesLabel(remaining: 24 * 60 + 13) == "24m")
        #expect(MenuBarIcon.minutesLabel(remaining: 60) == "1m")
        #expect(MenuBarIcon.minutesLabel(remaining: 59) == "<1m")
        #expect(MenuBarIcon.minutesLabel(remaining: 0) == "<1m")
        #expect(MenuBarIcon.minutesLabel(remaining: 90 * 60) == "90m")
    }

    private func coverage(_ state: PlayState) -> [Bool] {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuBarIcon.image(for: state).draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<18).flatMap { y in (0..<18).map { x in rep.colorAt(x: x, y: y)!.alphaComponent > 0.5 } }
    }

    /// Pixel at (x, y) counted from the top-left, like the SVG.
    private func filled(_ pixels: [Bool], _ x: Int, _ y: Int) -> Bool { pixels[y * 18 + x] }

    @Test func imagesAreTemplates() {
        for state in [PlayState.idle, .playing, .paused] {
            let image = MenuBarIcon.image(for: state)
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
        }
    }

    @Test func idleIsARingOnAThread() {
        let p = coverage(.idle)
        #expect(filled(p, 9, 2))  // thread
        #expect(!filled(p, 9, 11))  // hollow center
        #expect(filled(p, 4, 11))  // left of the ring
        #expect(filled(p, 13, 11))  // right of the ring
    }

    @Test func playingIsASolidBall() {
        let p = coverage(.playing)
        #expect(filled(p, 9, 2))
        #expect(filled(p, 9, 11))
        #expect(filled(p, 6, 11))
        #expect(filled(p, 12, 11))
    }

    @Test func pausedFillsTheLeftHalf() {
        let p = coverage(.paused)
        #expect(filled(p, 7, 11))  // left half is solid
        #expect(!filled(p, 10, 11))  // right half stays hollow
        #expect(filled(p, 13, 11))
    }
}
