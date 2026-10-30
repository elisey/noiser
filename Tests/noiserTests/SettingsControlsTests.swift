import AppKit
import Testing
@testable import noiser

private final class ActionSink: NSObject {
    var count = 0
    @objc func fire(_ sender: Any?) { count += 1 }
}

private func keyEvent(_ key: NSEvent.SpecialKey) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: String(Character(UnicodeScalar(key.rawValue)!)), charactersIgnoringModifiers: String(Character(UnicodeScalar(key.rawValue)!)),
        isARepeat: false, keyCode: 0
    )!
}

@MainActor struct SettingsControlsTests {
    @Test func presetsRoundTripThroughHex() {
        #expect(BallPreset.matching(nil) == .tomato)
        #expect(BallPreset.matching("#5A3CF0") == .violet)
        #expect(BallPreset.matching("#121212") == .ink)
        #expect(BallPreset.matching("#00FF00") == nil)
    }

    @Test func storedColorsResolve() {
        #expect(color(fromHex: nil) === Theme.ball)
        #expect(color(fromHex: "garbage") === Theme.ball)
        #expect(color(fromHex: BallPreset.inkHex) === Theme.ink)
        #expect(hex(from: color(fromHex: "#5A3CF0")) == "#5A3CF0")
    }

    @Test func decibelScaleUsesMinusSign() {
        #expect(SettingsWindow.decibels(-30) == "\u{2212}30 dB")
        #expect(SettingsWindow.decibels(12) == "+12 dB")
        #expect(SettingsWindow.decibels(0) == "0 dB")
    }

    @Test func segmentsSelectWithArrowKeys() {
        // Actions are dispatched through NSApp.
        _ = NSApplication.shared
        let sink = ActionSink()
        let pill = SegmentedPill(titles: ["White", "Pink", "Brown"], selectedIndex: 2)
        pill.frame = NSRect(x: 0, y: 0, width: 220, height: 34)
        pill.target = sink
        pill.action = #selector(ActionSink.fire(_:))

        pill.keyDown(with: keyEvent(.rightArrow))
        #expect(pill.selectedIndex == 2)
        #expect(sink.count == 0)

        pill.keyDown(with: keyEvent(.leftArrow))
        #expect(pill.selectedIndex == 1)
        #expect(sink.count == 1)
    }

    @Test func segmentsAreARadioGroup() throws {
        let pill = SegmentedPill(titles: ["White", "Pink", "Brown"], selectedIndex: 0)
        #expect(pill.accessibilityRole() == .radioGroup)
        let children = try #require(pill.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.count == 3)
        #expect(children.allSatisfy { $0.accessibilityRole() == .radioButton })
        #expect(children[1].accessibilityLabel() == "Pink")
        #expect(children[0].accessibilityValue() as? NSNumber == 1)
        #expect(children[1].accessibilityPerformPress())
        #expect(pill.selectedIndex == 1)
        #expect(pill.accessibilityValue() as? String == "Pink")
    }

    @Test func segmentsSplitTheInnerWidthEvenly() {
        let pill = SegmentedPill(titles: ["A", "B", "C"], selectedIndex: 0)
        pill.frame = NSRect(x: 0, y: 0, width: 220, height: 34)
        let widths = (0..<3).map { pill.segmentFrame($0).width }
        #expect(widths.allSatisfy { abs($0 - 214.0 / 3) < 0.001 })
        #expect(pill.segmentFrame(0).minX == 3)
        #expect(pill.segmentFrame(0).height == 28)
        #expect(abs(pill.segmentFrame(2).maxX - 217) < 0.001)
    }

    @Test func sliderKnobTravelsTheWholeTrack() {
        let cell = VolumeSliderCell()
        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 244, height: 24))
        slider.cell = cell
        cell.minValue = -30
        cell.maxValue = 12
        let track = cell.barRect(flipped: false)
        #expect(track.minX == 12)
        #expect(track.width == 220)
        #expect(track.height == 6)

        cell.doubleValue = -30
        #expect(cell.knobRect(flipped: false).midX == track.minX)
        cell.doubleValue = 12
        #expect(cell.knobRect(flipped: false).midX == track.maxX)
        #expect(cell.knobRect(flipped: false).width == 24)
    }

    @Test func settingsWindowChangesTheBallColor() throws {
        let settings = Settings()
        let saved = settings.ballColor
        defer { settings.ballColor = saved }
        settings.ballColor = nil

        let panel = SettingsWindow(settings: settings)
        var changes = 0
        panel.onColorChanged = { changes += 1 }
        let swatches = panel.window.contentView!.subviews.compactMap { $0 as? SwatchButton }
        #expect(swatches.count == 4)
        #expect(swatches[0].isSelected)

        swatches[1].performClick(nil)
        #expect(settings.ballColor == "#5A3CF0")
        #expect(swatches[1].isSelected && !swatches[0].isSelected)

        swatches[2].performClick(nil)
        #expect(settings.ballColor == BallPreset.inkHex)

        swatches[0].performClick(nil)
        #expect(settings.ballColor == nil)
        #expect(changes == 3)
        panel.window.close()
    }

    @Test func settingsWindowHasNoCloseButtonAndClosesOnEscape() {
        let panel = SettingsWindow(settings: Settings())
        let buttons = panel.window.contentView!.subviews.compactMap { $0 as? NSButton }
        #expect(!buttons.contains { $0.title == "Close" })
        #expect(panel.window.frame.width == Theme.Metrics.settingsWidth)
        panel.window.orderFront(nil)
        #expect(panel.window.isVisible)
        panel.window.cancelOperation(nil)
        #expect(!panel.window.isVisible)
    }

    @Test func checkboxTogglesState() {
        // Actions are dispatched through NSApp.
        _ = NSApplication.shared
        let sink = ActionSink()
        let box = InkCheckbox(title: "Announce", target: sink, action: #selector(ActionSink.fire(_:)))
        box.state = .on
        box.performClick(nil)
        #expect(box.state == .off)
        #expect(sink.count == 1)
        #expect(box.frame.height == 20)
    }
}
