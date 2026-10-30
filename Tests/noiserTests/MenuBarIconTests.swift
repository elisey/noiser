import AppKit
import Testing
@testable import noiser

struct MenuBarIconTests {
    @Test func labelForEachState() {
        #expect(MenuBarIcon.label(state: .idle, remaining: nil) == "0m")
        #expect(MenuBarIcon.label(state: .playing, remaining: nil) == "∞")
        #expect(MenuBarIcon.label(state: .paused, remaining: nil) == "∞")
        #expect(MenuBarIcon.label(state: .playing, remaining: 24 * 60 + 13) == "24m")
        #expect(MenuBarIcon.label(state: .paused, remaining: 24 * 60 + 13) == "24m")
        #expect(MenuBarIcon.label(state: .playing, remaining: 60) == "1m")
        #expect(MenuBarIcon.label(state: .playing, remaining: 59) == "<1m")
        #expect(MenuBarIcon.label(state: .playing, remaining: 0) == "<1m")
        #expect(MenuBarIcon.label(state: .playing, remaining: 99 * 60 + 59) == "99m")
        #expect(MenuBarIcon.label(state: .playing, remaining: 100 * 60) == ">1h")
        #expect(MenuBarIcon.label(state: .playing, remaining: 150 * 60) == ">2h")
        #expect(MenuBarIcon.label(state: .paused, remaining: 9 * 3600 + 59) == ">9h")
    }

    @Test func statusImageKeepsItsWidth() {
        Theme.registerFonts(url: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/Fonts/Archivo.ttf"))
        let images = [
            MenuBarIcon.image(for: .idle, label: "0m"),
            MenuBarIcon.image(for: .playing, label: "∞"),
            MenuBarIcon.image(for: .playing, label: "<1m"),
            MenuBarIcon.image(for: .playing, label: "24m"),
            MenuBarIcon.image(for: .paused, label: ">2h"),
        ]
        let size = MenuBarIcon.size
        #expect(images.allSatisfy { $0.size == size && $0.isTemplate })
        #expect(size.height == 18)
        // Every label the status item can show fits in the reserved width.
        for label in ["0m", "<1m", "24m", "99m", ">1h", ">9h"] {
            let width = Theme.menubar.string(label, color: .black).size().width
            #expect(MenuBarIcon.markSize.width + MenuBarIcon.gap + width <= size.width)
        }
    }

    private func coverage(_ state: PlayState) -> [Bool] {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuBarIcon.markImage(for: state).draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<18).flatMap { y in (0..<18).map { x in rep.colorAt(x: x, y: y)!.alphaComponent > 0.5 } }
    }

    /// Pixel at (x, y) counted from the top-left, like the SVG.
    private func filled(_ pixels: [Bool], _ x: Int, _ y: Int) -> Bool { pixels[y * 18 + x] }

    @Test func marksAreTemplates() {
        for state in [PlayState.idle, .playing, .paused] {
            let image = MenuBarIcon.markImage(for: state)
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
