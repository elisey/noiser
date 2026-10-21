import Foundation

enum NoiseKind: Int, CaseIterable {
    case white, pink, brown

    var key: String {
        switch self {
        case .white: return "white"
        case .pink: return "pink"
        case .brown: return "brown"
        }
    }

    var title: String { key.capitalized }

    init?(key: String) {
        guard let kind = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = kind
    }
}

/// Direct form II transposed IIR filter. Coefficients are normalized so a[0] == 1 and
/// both arrays are padded to the same length, which keeps the per-sample loop branch-free.
struct IIRFilter {
    private let b: [Double]
    private let a: [Double]
    private var z: [Double]

    init(b: [Double], a: [Double]) {
        let order = max(b.count, a.count) - 1
        let a0 = a[0]
        self.b = (0...order).map { $0 < b.count ? b[$0] / a0 : 0 }
        self.a = (0...order).map { $0 < a.count ? a[$0] / a0 : 0 }
        z = Array(repeating: 0, count: order)
    }

    mutating func reset() {
        for i in z.indices { z[i] = 0 }
    }

    @inline(__always)
    mutating func process(_ x: Double) -> Double {
        let order = z.count
        let y = b[0] * x + z[0]
        var i = 0
        while i < order - 1 {
            z[i] = b[i + 1] * x - a[i + 1] * y + z[i + 1]
            i += 1
        }
        z[order - 1] = b[order] * x - a[order] * y
        return y
    }

    /// Second-order Butterworth high-pass via the bilinear transform with the cutoff prewarped,
    /// so the -3 dB point lands exactly on `cutoff`.
    static func butterworthHighPass(cutoff: Double, sampleRate: Double) -> IIRFilter {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * sqrt(0.5))
        let c = cos(w0)
        return IIRFilter(
            b: [(1 + c) / 2, -(1 + c), (1 + c) / 2],
            a: [1 + alpha, -2 * c, 1 - alpha]
        )
    }
}

/// Cascade of filters that colors white noise; empty for white itself.
struct NoiseFilter {
    private var stages: [IIRFilter]

    init(stages: [IIRFilter]) {
        self.stages = stages
    }

    mutating func reset() {
        for i in stages.indices { stages[i].reset() }
    }

    @inline(__always)
    mutating func process(_ x: Double) -> Double {
        var y = x
        for i in stages.indices { y = stages[i].process(y) }
        return y
    }
}

/// xoshiro256** feeding Box-Muller. `SystemRandomNumberGenerator` is avoided on purpose:
/// it calls into the kernel and may lock, which is unacceptable on the audio render thread.
struct GaussianNoise {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64
    private var spare = 0.0
    private var hasSpare = false

    init() {
        var seed = UInt64.random(in: .min ... .max)
        func splitmix() -> UInt64 {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = splitmix()
        s1 = splitmix()
        s2 = splitmix()
        s3 = splitmix()
    }

    @inline(__always)
    private mutating func nextBits() -> UInt64 {
        let result = ((s1 &* 5) << 7 | (s1 &* 5) >> 57) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = s3 << 45 | s3 >> 19
        return result
    }

    /// Uniform in (0, 1]; never 0 so the logarithm below stays finite.
    @inline(__always)
    private mutating func nextUniform() -> Double {
        Double((nextBits() >> 11) + 1) * 0x1.0p-53
    }

    /// Standard normal sample.
    @inline(__always)
    mutating func next() -> Double {
        if hasSpare {
            hasSpare = false
            return spare
        }
        let r = sqrt(-2 * log(nextUniform()))
        let theta = 2 * Double.pi * nextUniform()
        spare = r * sin(theta)
        hasSpare = true
        return r * cos(theta)
    }
}
