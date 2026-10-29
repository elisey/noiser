import Testing
@testable import noiser

struct PopoverDisplayTests {
    private func make(
        _ state: PlayState, remaining: Double? = nil, drag: Int? = nil, timeIsUp: Bool = false
    ) -> PopoverDisplay {
        PopoverDisplay.make(state: state, remaining: remaining, dragMinutes: drag, timeIsUp: timeIsUp)
    }

    @Test func idle() {
        let d = make(.idle)
        #expect(d.time == "00:00")
        #expect(d.timeTone == .faint)
        #expect(d.pill == "drag or click")
        #expect(d.pillLook == .outline)
        #expect(d.ball == .solid)
        #expect(!d.ghost)
    }

    @Test func playing() {
        let d = make(.playing, remaining: 24 * 60 + 13)
        #expect(d.time == "24:13")
        #expect(d.timeTone == .ink)
        #expect(!d.longTime)
        #expect(d.pill == "playing")
        #expect(d.pillLook == .ink)
        #expect(d.ball == .solid)
    }

    @Test func playingWithHoursUsesLongStyle() {
        let d = make(.playing, remaining: 3900)
        #expect(d.time == "1:05:00")
        #expect(d.longTime)
    }

    @Test func playingWithoutTimer() {
        #expect(make(.playing).time == "∞")
    }

    @Test func paused() {
        let d = make(.paused, remaining: 24 * 60 + 13)
        #expect(d.time == "24:13")
        #expect(d.timeTone == .ink)
        #expect(d.pill == "paused")
        #expect(d.pillLook == .outline)
        #expect(d.ball == .ring)
    }

    @Test func draggingAMinuteOrMore() {
        let d = make(.idle, drag: 25)
        #expect(d.time == "25m")
        #expect(d.pill == "release — start")
        #expect(d.pillLook == .lime)
        #expect(d.ghost)
        #expect(make(.playing, remaining: 100, drag: 90).time == "1h 30m")
    }

    @Test func draggingUnderAMinute() {
        let d = make(.paused, remaining: 100, drag: 0)
        #expect(d.time == "∞")
        #expect(d.pill == "release — no timer")
        #expect(d.pillLook == .lime)
        #expect(d.ghost)
    }

    @Test func timeIsUp() {
        let d = make(.idle, timeIsUp: true)
        #expect(d.time == "00:00")
        #expect(d.timeTone == .ink)
        #expect(d.pill == "time is up")
        #expect(d.pillLook == .tomato)
    }

    @Test func timeIsUpGivesWayToANewRun() {
        #expect(make(.playing, remaining: 60, timeIsUp: true).pill == "playing")
    }
}
