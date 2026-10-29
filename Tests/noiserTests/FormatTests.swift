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
}
