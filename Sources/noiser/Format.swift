import Foundation

// Drag distance -> duration. Centimeters are nominal (macOS assumes 72 pt per inch),
// so tune `minutesPerCm` against a ruler on your own screen.
enum Duration {
    static let minutesPerCm = 5.0
    static let pointsPerCm = 72.0 / 2.54
    static let minMinutes = 1
    // (upper bound in minutes, rounding step); nil bound = everything above.
    static let roundingSteps: [(limit: Double?, step: Double)] = [(30, 1), (60, 5), (nil, 10)]

    static func roundMinutes(_ raw: Double) -> Int {
        for (limit, step) in roundingSteps where limit == nil || raw < limit! {
            return Int((raw / step).rounded(.toNearestOrEven) * step)
        }
        return Int(raw.rounded())
    }

    /// 0 means the pull was too short to count as a duration (i.e. a click).
    static func dragMinutes(points: Double) -> Int {
        let raw = points / pointsPerCm * minutesPerCm
        if raw < Double(minMinutes) { return 0 }
        return max(minMinutes, roundMinutes(raw))
    }

    static func hms(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
    }

    static func minutes(_ minutes: Int) -> String {
        let (h, m) = minutes.quotientAndRemainder(dividingBy: 60)
        return [h > 0 ? "\(h)h" : "", m > 0 ? "\(m)m" : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
