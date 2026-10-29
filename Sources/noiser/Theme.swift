import AppKit
import CoreText

/// Colors, metrics and type styles of the interface; values come from docs/redesign/tokens.json.
enum Theme {
    // MARK: Colors

    static let paper = dynamic("paper", light: 0xF1EADF, dark: 0x121212)
    static let paperDeep = dynamic("paperDeep", light: 0xE6DCCC, dark: 0x1F1E1C)
    static let hairline = dynamic("hairline", light: 0xD6CAB7, dark: 0x34322F)
    static let ink = dynamic("ink", light: 0x121212, dark: 0xF1EADF)
    static let inkMuted = dynamic("inkMuted", light: 0x5E574D, dark: 0xB5AC9E)
    static let inkFaint = dynamic("inkFaint", light: 0x857D71, dark: 0x7F786C)
    static let onInk = paper
    static let ball = dynamic("ball", light: 0xF2431F, dark: 0xFF4F2B)
    static let tomato = rgb(0xFF4F2B)
    static let lime = rgb(0xD4F53C)
    static let violet = rgb(0x5A3CF0)
    static let coal = rgb(0x121212)
    static let cream = rgb(0xF1EADF)

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        let lightColor = rgb(light), darkColor = rgb(dark)
        return NSColor(name: NSColor.Name(name)) { appearance in
            isDark(appearance) ? darkColor : lightColor
        }
    }

    // MARK: Metrics

    enum Metrics {
        /// The popover and everything in it (ball, thread, type, buttons) is drawn at this
        /// fraction of the design-system sizes; the settings window and menu bar are not.
        static let popoverScale: CGFloat = 0.85

        /// A popover size from the design system, scaled.
        static func popover(_ value: CGFloat) -> CGFloat { value * popoverScale }

        static let popoverWidth = popover(232)
        static let popoverHeight = popover(220)
        static let ballDiameter = popover(64)
        static let threadWidth = popover(18)
        /// From the top of the content to the top of the ball, plus the overlap into the ball.
        static let threadLength = popover(48)
        static let ballTop = popover(38)
        static let timeTop = popover(116)
        static let timeLineHeight = popover(46)
        static let pillTop = popover(176)
        static let pillHeight = popover(24)
        static let iconButton = popover(24)
        static let iconInset = popover(12)
        static let popoverRadius = popover(22)
        static let settingsWidth: CGFloat = 360
    }

    // MARK: Fonts

    static let fontFamily = "Archivo"
    /// Set once the bundled Archivo has been registered; until then fonts fall back to the system font.
    private(set) static var fontAvailable = false

    /// Registers the bundled Archivo for this process. Returns false (and logs) if it can't be loaded.
    @discardableResult
    static func registerFonts(
        url: URL? = Bundle.main.url(forResource: "Archivo", withExtension: "ttf", subdirectory: "Fonts")
    ) -> Bool {
        guard let url else {
            NSLog("noiser: Archivo.ttf is not in the bundle, using the system font")
            return false
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let cfError = error?.takeRetainedValue()
            let alreadyRegistered = cfError.map {
                CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue
            } ?? false
            if !alreadyRegistered {
                NSLog("noiser: failed to register %@: %@", url.path, cfError.map { "\($0)" } ?? "unknown error")
                return false
            }
        }
        fontAvailable = true
        return true
    }

    private static let widthAxis = 0x7764_7468  // 'wdth'
    private static let weightAxis = 0x7767_6874  // 'wght'

    /// Archivo at an arbitrary point of its width (62–125) and weight (100–900) axes.
    static func font(size: CGFloat, weight: CGFloat, width: CGFloat = 125, tabular: Bool = false) -> NSFont {
        guard fontAvailable else { return fallbackFont(size: size, weight: weight, tabular: tabular) }
        var attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: fontFamily,
            kCTFontVariationAttribute: [widthAxis: width, weightAxis: weight] as [Int: CGFloat],
        ]
        if tabular {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
            ]]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        guard CTFontCopyFamilyName(font) as String == fontFamily else {
            return fallbackFont(size: size, weight: weight, tabular: tabular)
        }
        return font as NSFont
    }

    private static func fallbackFont(size: CGFloat, weight: CGFloat, tabular: Bool) -> NSFont {
        let systemWeight = systemWeight(weight)
        return tabular
            ? .monospacedDigitSystemFont(ofSize: size, weight: systemWeight)
            : .systemFont(ofSize: size, weight: systemWeight)
    }

    /// Maps a CSS-style weight (100–900) to the nearest system font weight.
    static func systemWeight(_ weight: CGFloat) -> NSFont.Weight {
        let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let index = Int((weight / 100).rounded()) - 1
        return weights[min(max(index, 0), weights.count - 1)]
    }

    // MARK: Text styles

    struct TextStyle {
        let size: CGFloat
        let weight: CGFloat
        var width: CGFloat = 125
        /// Letter spacing in em.
        var tracking: CGFloat = 0
        var uppercase = false
        var tabular = false

        var font: NSFont {
            Theme.font(size: size, weight: weight, width: width, tabular: tabular)
        }

        func attributes(color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .kern: tracking * size]
        }

        func string(_ text: String, color: NSColor) -> NSAttributedString {
            let result = NSMutableAttributedString(
                string: uppercase ? text.uppercased() : text,
                attributes: attributes(color: color)
            )
            // Tracking goes between letters; after the last one it would only shift the centering.
            if let last = result.string.indices.last {
                let range = NSRange(last..<result.string.endIndex, in: result.string)
                result.removeAttribute(.kern, range: range)
            }
            return result
        }
    }

    static let time = TextStyle(size: Metrics.popover(46), weight: 900, tracking: -0.05, tabular: true)
    static let timeLong = TextStyle(size: Metrics.popover(36), weight: 900, tracking: -0.05, tabular: true)
    static let pill = TextStyle(size: Metrics.popover(11), weight: 900, tracking: 0.04, uppercase: true)
    static let label = TextStyle(size: 13, weight: 700)
    static let caption = TextStyle(size: 12, weight: 600, tracking: 0.04, uppercase: true)
    static let menubar = TextStyle(size: 13, weight: 800, tabular: true)
    static let windowTitle = TextStyle(size: 15, weight: 900, tracking: -0.04)
    static let body = TextStyle(size: 15, weight: 400, width: 100)
}
