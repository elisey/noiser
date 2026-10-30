import Testing
@testable import noiser

struct FormatTests {
    @Test func hmsUnderAnHourHasNoHours() {
        #expect(Duration.hms(0) == "00:00")
        #expect(Duration.hms(24 * 60 + 13) == "24:13")
        #expect(Duration.hms(3599.9) == "59:59")
    }

    @Test func hmsWithHoursHasNoLeadingZero() {
        #expect(Duration.hms(3600) == "1:00:00")
        #expect(Duration.hms(3900) == "1:05:00")
        #expect(Duration.hms(10 * 3600 + 61) == "10:01:01")
    }

    @Test func hmsClampsNegative() {
        #expect(Duration.hms(-5) == "00:00")
    }

    @Test func minutesLabel() {
        #expect(Duration.minutes(25) == "25m")
        #expect(Duration.minutes(90) == "1h 30m")
        #expect(Duration.minutes(120) == "2h")
    }

    // Pull distance in cm that reaches the end of each bounded segment.
    private func segmentEndsCm() -> [Double] {
        var ends: [Double] = []
        var minutes = 0.0
        var cm = 0.0
        for (limit, rate) in Duration.dragRates {
            guard let limit else { break }
            cm += (limit - minutes) / rate
            minutes = limit
            ends.append(cm)
        }
        return ends
    }

    @Test func rawMinutesUsesFirstRateInFirstSegment() {
        #expect(Duration.rawMinutes(cm: 0) == 0)
        #expect(Duration.rawMinutes(cm: 1) == Duration.dragRates[0].minutesPerCm)
    }

    @Test func rawMinutesIsContinuousAtSegmentBounds() {
        for (end, segment) in zip(segmentEndsCm(), Duration.dragRates) {
            #expect(abs(Duration.rawMinutes(cm: end) - segment.limit!) < 1e-9)
        }
    }

    @Test func rawMinutesUsesEachSegmentRate() {
        let ends = segmentEndsCm()
        for (i, end) in ends.enumerated() {
            let next = Duration.dragRates[i + 1]
            let raw = Duration.rawMinutes(cm: end + 1)
            #expect(abs(raw - (Duration.dragRates[i].limit! + next.minutesPerCm)) < 1e-9)
        }
    }

    @Test func dragMinutesFollowsPiecewiseScale() {
        // 10 cm past the two-hour bound adds 10 cm at the third segment's rate.
        let twoHoursCm = segmentEndsCm()[1]
        let points = (twoHoursCm + 10) * Duration.pointsPerCm
        #expect(Duration.dragMinutes(points: points) == 120 + Int(10 * Duration.dragRates[2].minutesPerCm))
        #expect(Duration.dragMinutes(points: 0) == 0)
    }

    @Test func roundMinutesUsesWholeHoursPastTenHours() {
        #expect(Duration.roundMinutes(599) == 600)
        #expect(Duration.roundMinutes(640) == 660)
        #expect(Duration.roundMinutes(689) == 660)
        #expect(Duration.minutes(Duration.roundMinutes(725)) == "12h")
    }

    @Test func longPullsShowOnlyHours() {
        let tenHoursCm = segmentEndsCm()[2]
        for extraCm in stride(from: 0.0, through: 10.0, by: 0.25) {
            let minutes = Duration.dragMinutes(points: (tenHoursCm + extraCm) * Duration.pointsPerCm)
            #expect(minutes % 60 == 0)
            #expect(!Duration.minutes(minutes).contains("m"))
        }
    }
}
