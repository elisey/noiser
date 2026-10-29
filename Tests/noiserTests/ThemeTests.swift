import AppKit
import CoreText
import Testing
@testable import noiser

private let fontURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Support/Fonts/Archivo.ttf")

private func resolved(_ color: NSColor, dark: Bool) -> String {
    var result = ""
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        result = hex(from: color)
    }
    return result
}

private func axisValue(_ font: NSFont, _ tag: Int) -> Double? {
    let variation = CTFontCopyVariation(font) as? [Int: Double]
    return variation?[tag]
}

@Suite(.serialized) struct ThemeTests {
    @Test func dynamicColorsFollowAppearance() {
        let expected: [(NSColor, String, String)] = [
            (Theme.paper, "#F1EADF", "#121212"),
            (Theme.paperDeep, "#E6DCCC", "#1F1E1C"),
            (Theme.hairline, "#D6CAB7", "#34322F"),
            (Theme.ink, "#121212", "#F1EADF"),
            (Theme.inkMuted, "#5E574D", "#B5AC9E"),
            (Theme.inkFaint, "#857D71", "#7F786C"),
            (Theme.onInk, "#F1EADF", "#121212"),
            (Theme.ball, "#F2431F", "#FF4F2B"),
        ]
        for (color, light, dark) in expected {
            #expect(resolved(color, dark: false) == light)
            #expect(resolved(color, dark: true) == dark)
        }
    }

    @Test func fixedColorsIgnoreAppearance() {
        let expected: [(NSColor, String)] = [
            (Theme.tomato, "#FF4F2B"), (Theme.lime, "#D4F53C"), (Theme.violet, "#5A3CF0"),
            (Theme.coal, "#121212"), (Theme.cream, "#F1EADF"),
        ]
        for (color, value) in expected {
            #expect(resolved(color, dark: false) == value)
            #expect(resolved(color, dark: true) == value)
        }
    }

    @Test func missingFontFileFallsBackToSystemFont() {
        let missing = URL(fileURLWithPath: "/nonexistent/Archivo.ttf")
        #expect(Theme.registerFonts(url: nil) == false)
        #expect(Theme.registerFonts(url: missing) == false)
    }

    @Test func systemWeightMapping() {
        #expect(Theme.systemWeight(900) == .black)
        #expect(Theme.systemWeight(700) == .bold)
        #expect(Theme.systemWeight(400) == .regular)
        #expect(Theme.systemWeight(1200) == .black)
        #expect(Theme.systemWeight(0) == .ultraLight)
    }

    @Test func archivoAppliesWidthAndWeightAxes() throws {
        #expect(Theme.registerFonts(url: fontURL))
        // Registering twice must not count as a failure.
        #expect(Theme.registerFonts(url: fontURL))

        let font = Theme.font(size: 46, weight: 900, width: 125)
        #expect(font.familyName == "Archivo")
        #expect(axisValue(font, 0x7764_7468) == 125)
        #expect(axisValue(font, 0x7767_6874) == 900)

        let sample = "24:13"
        let wide = NSAttributedString(string: sample, attributes: [.font: font]).size().width
        let narrow = NSAttributedString(string: sample, attributes: [.font: Theme.font(size: 46, weight: 900, width: 62)]).size().width
        #expect(wide > narrow * 1.3)
    }

    @Test func tabularFiguresHaveEqualAdvances() {
        #expect(Theme.registerFonts(url: fontURL))
        let font = Theme.time.font
        let one = NSAttributedString(string: "1", attributes: [.font: font]).size().width
        let eight = NSAttributedString(string: "8", attributes: [.font: font]).size().width
        #expect(abs(one - eight) < 0.01)
    }

    @Test func popoverIsScaledAsAWhole() {
        typealias M = Theme.Metrics
        #expect(M.popoverScale == 0.85)
        let scaled: [(CGFloat, CGFloat)] = [
            (M.popoverWidth, 232), (M.popoverHeight, 220), (M.ballDiameter, 64), (M.threadWidth, 18),
            (M.ballTop, 38), (M.timeTop, 116), (M.timeLineHeight, 46), (M.pillTop, 176), (M.pillHeight, 24),
            (M.iconButton, 24), (M.iconInset, 12),
            (Theme.time.size, 46), (Theme.timeLong.size, 36), (Theme.pill.size, 11),
        ]
        for (value, design) in scaled {
            #expect(value == design * M.popoverScale)
        }
        // The thread keeps the mark's proportion to the ball.
        #expect(abs(M.threadWidth / M.ballDiameter - 0.28) < 0.01)
        // Outside the popover nothing is scaled.
        #expect(M.settingsWidth == 360)
        #expect(Theme.label.size == 13)
        #expect(Theme.menubar.size == 13)
    }

    @Test func textStyleAppliesTrackingAndCase() {
        let text = Theme.pill.string("playing", color: Theme.ink)
        #expect(text.string == "PLAYING")
        let kern = text.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(kern == Theme.pill.size * 0.04)
        #expect(text.attribute(.kern, at: text.length - 1, effectiveRange: nil) == nil)
        #expect(Theme.time.string("24:13", color: Theme.ink).string == "24:13")
    }
}
