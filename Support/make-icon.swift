// Renders the app icon. Usage:
//   swift Support/make-icon.swift preview <dir>   # every variant at 512 px, for picking one
//   swift Support/make-icon.swift icns <variant> <out.iconset-dir>
import AppKit

let canvas: CGFloat = 1024
// Apple's icon grid: the shape is 824 pt centered on a 1024 pt canvas.
let shapeRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shapeRadius: CGFloat = 186

struct Palette {
    let top: NSColor
    let bottom: NSColor
    let ball: NSColor
    let line: NSColor
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

func background(_ p: Palette) {
    let path = NSBezierPath(roundedRect: shapeRect, xRadius: shapeRadius, yRadius: shapeRadius)
    NSGradient(starting: p.top, ending: p.bottom)!.draw(in: path, angle: -90)
    // Soft inner highlight along the top edge, like the system icons.
    NSGraphicsContext.current!.saveGraphicsState()
    path.addClip()
    let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: .clear)!
    glow.draw(in: CGRect(x: 100, y: 924 - 260, width: 824, height: 260), angle: 90)
    NSGraphicsContext.current!.restoreGraphicsState()
}

func ball(at c: CGPoint, r: CGFloat, color: NSColor) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.18), blur: r * 0.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color.setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    ctx.restoreGState()
    // Specular highlight.
    let hl = NSGradient(starting: NSColor.white.withAlphaComponent(0.55), ending: .clear)!
    let hr = CGRect(x: c.x - r * 0.75, y: c.y - r * 0.15, width: r * 1.5, height: r * 1.1)
    hl.draw(in: NSBezierPath(ovalIn: hr), relativeCenterPosition: CGPoint(x: -0.2, y: 0.4))
}

func string(from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.lineWidth = width
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

/// Smooth noise line: a random walk pulled back to zero, then low-passed. Deterministic seed.
func noiseWave(in rect: CGRect, points: Int, seed: UInt64, roughness: CGFloat) -> NSBezierPath {
    var s = seed
    func rnd() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(s >> 11) / Double(1 << 53)) * 2 - 1
    }
    var y: CGFloat = 0, v: CGFloat = 0
    let path = NSBezierPath()
    for i in 0..<points {
        v = v * 0.7 + rnd() * roughness
        y = (y + v) * 0.92
        let x = rect.minX + rect.width * CGFloat(i) / CGFloat(points - 1)
        let py = rect.midY + max(-1, min(1, y)) * rect.height / 2
        i == 0 ? path.move(to: CGPoint(x: x, y: py)) : path.line(to: CGPoint(x: x, y: py))
    }
    return path
}

// MARK: - Variants

let variants: [(name: String, draw: () -> Void)] = [
    ("ball", {
        // The signature gesture: a ball pulled on its string.
        let p = Palette(top: rgb(46, 54, 84), bottom: rgb(22, 26, 44), ball: rgb(255, 122, 89), line: rgb(190, 198, 220))
        background(p)
        let anchor = CGPoint(x: 512, y: 924)
        let center = CGPoint(x: 600, y: 420)
        string(from: anchor, to: center, color: p.line, width: 14)
        ball(at: center, r: 150, color: p.ball)
    }),
    ("wave", {
        // Brown noise itself: a slow, smooth wave on a warm ground.
        let p = Palette(top: rgb(128, 84, 58), bottom: rgb(70, 42, 28), ball: .white, line: rgb(255, 236, 214))
        background(p)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        NSBezierPath(roundedRect: shapeRect, xRadius: shapeRadius, yRadius: shapeRadius).addClip()
        for (i, alpha) in [(0, 0.25), (1, 0.45), (2, 1.0)] {
            let path = noiseWave(in: CGRect(x: 60, y: 300, width: 904, height: 420), points: 160, seed: UInt64(11 + i * 7), roughness: 0.22)
            path.lineWidth = i == 2 ? 30 : 18
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            p.line.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
        ctx.restoreGState()
    }),
    ("ball-wave", {
        // Both ideas: the ball hangs over the noise it controls.
        let p = Palette(top: rgb(28, 94, 104), bottom: rgb(14, 48, 58), ball: rgb(255, 196, 87), line: rgb(214, 236, 236))
        background(p)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        NSBezierPath(roundedRect: shapeRect, xRadius: shapeRadius, yRadius: shapeRadius).addClip()
        let wave = noiseWave(in: CGRect(x: 60, y: 160, width: 904, height: 260), points: 160, seed: 29, roughness: 0.2)
        wave.lineWidth = 22
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        p.line.withAlphaComponent(0.55).setStroke()
        wave.stroke()
        ctx.restoreGState()
        let anchor = CGPoint(x: 512, y: 924)
        let center = CGPoint(x: 512, y: 540)
        string(from: anchor, to: center, color: p.line, width: 12)
        ball(at: center, r: 130, color: p.ball)
    }),
    ("ripple", {
        // Sound spreading from the ball: concentric rings fading out.
        let p = Palette(top: rgb(40, 40, 46), bottom: rgb(16, 16, 20), ball: rgb(120, 200, 255), line: rgb(120, 200, 255))
        background(p)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        NSBezierPath(roundedRect: shapeRect, xRadius: shapeRadius, yRadius: shapeRadius).addClip()
        let c = CGPoint(x: 512, y: 512)
        for i in 1...4 {
            let r = CGFloat(130 + i * 95)
            let ring = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ring.lineWidth = 16
            p.line.withAlphaComponent(1.0 - CGFloat(i) * 0.2).setStroke()
            ring.stroke()
        }
        ctx.restoreGState()
        ball(at: c, r: 110, color: p.ball)
    }),
]

// MARK: - Output

func render(_ draw: () -> Void, size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "preview":
    let dir = URL(fileURLWithPath: args[2])
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for v in variants {
        try! render(v.draw, size: 512).write(to: dir.appendingPathComponent("\(v.name).png"))
    }
case "icns":
    guard let v = variants.first(where: { $0.name == args[2] }) else {
        FileHandle.standardError.write("unknown variant \(args[2]); have: \(variants.map(\.name))\n".data(using: .utf8)!)
        exit(1)
    }
    let dir = URL(fileURLWithPath: args[3])
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try! render(v.draw, size: base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
        try! render(v.draw, size: base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
default:
    FileHandle.standardError.write("usage: make-icon.swift preview <dir> | icns <variant> <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
