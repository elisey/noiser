import AppKit

/// The status item: the ball-on-a-thread mark, plus the minutes left while a timer runs.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    /// Template image drawn on an 18×18 grid (see docs/redesign/assets/menubar-*.svg).
    static func image(for state: PlayState) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            let center = NSPoint(x: 9, y: 11.75)
            let threadLength: CGFloat = state == .playing ? 7.5 : 6.5
            NSBezierPath(roundedRect: NSRect(x: 7.5, y: 0.5, width: 3, height: threadLength), xRadius: 1.5, yRadius: 1.5).fill()

            if state == .playing {
                let r: CGFloat = 5.5
                NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
                return true
            }
            let r: CGFloat = 4.55
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            ring.lineWidth = 1.9
            ring.stroke()
            if state == .paused {
                // Left half of the ball, covering the ring's outer edge.
                let half = NSBezierPath()
                half.appendArc(withCenter: center, radius: 5.5, startAngle: 90, endAngle: 270)
                half.close()
                half.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "noiser"
        return image
    }

    /// "24m", "<1m" in the last minute; nil without a timer.
    static func minutesLabel(remaining: Double?) -> String? {
        guard let remaining else { return nil }
        let minutes = Int(max(0, remaining) / 60)
        return minutes < 1 ? "<1m" : "\(minutes)m"
    }

    /// Menu bar text in Archivo; the color is left to the status bar so it follows the menu bar appearance.
    static func title(_ text: String) -> NSAttributedString {
        var attributes = Theme.menubar.attributes(color: .labelColor)
        attributes.removeValue(forKey: .foregroundColor)
        return NSAttributedString(string: text, attributes: attributes)
    }
}
