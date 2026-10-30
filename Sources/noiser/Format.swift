import Foundation

// Drag distance -> duration. Centimeters are nominal (macOS assumes 72 pt per inch),
// so tune the rates against a ruler on your own screen.
// The scale is piecewise linear: each segment has its own rate.
enum Duration {
    // (upper bound in minutes, minutes per cm); nil bound = everything above.
    static let dragRates: [(limit: Double?, minutesPerCm: Double)] = [(60, 3.65), (120, 7.0), (600, 10.0), (nil, 60.0)]
    static let pointsPerCm = 72.0 / 2.54
    static let minMinutes = 1
    // (upper bound in minutes, rounding step); nil bound = everything above.
    // Whole hours past 10h, so long pulls show only hours.
    static let roundingSteps: [(limit: Double?, step: Double)] = [(30, 1), (60, 5), (600, 10), (nil, 60)]

    static func roundMinutes(_ raw: Double) -> Int {
        for (limit, step) in roundingSteps where limit == nil || raw < limit! {
            return Int((raw / step).rounded(.toNearestOrEven) * step)
        }
        return Int(raw.rounded())
    }

    static func rawMinutes(cm: Double) -> Double {
        var minutes = 0.0
        var cmLeft = cm
        for (limit, rate) in dragRates {
            guard let limit else { return minutes + cmLeft * rate }
            let segmentCm = (limit - minutes) / rate
            if cmLeft <= segmentCm { return minutes + cmLeft * rate }
            minutes = limit
            cmLeft -= segmentCm
        }
        return minutes
    }

    /// 0 means the pull was too short to count as a duration (i.e. a click).
    static func dragMinutes(points: Double) -> Int {
        let raw = rawMinutes(cm: points / pointsPerCm)
        if raw < Double(minMinutes) { return 0 }
        return max(minMinutes, roundMinutes(raw))
    }

    /// "24:13" under an hour, "1:05:00" with hours.
    static func hms(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let (h, m, sec) = (s / 3600, s % 3600 / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func minutes(_ minutes: Int) -> String {
        let (h, m) = minutes.quotientAndRemainder(dividingBy: 60)
        return [h > 0 ? "\(h)h" : "", m > 0 ? "\(m)m" : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
