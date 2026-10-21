import Foundation

/// UserDefaults-backed; every property validates on read so a hand-edited plist cannot break the app.
final class Settings {
    private enum Key {
        static let noise = "noise"
        static let volumeDb = "volumeDb"
        static let announce = "announce"
        static let ballColor = "ballColor"
    }

    private let defaults = UserDefaults.standard

    var noise: NoiseKind {
        get { defaults.string(forKey: Key.noise).flatMap(NoiseKind.init(key:)) ?? .brown }
        set { defaults.set(newValue.key, forKey: Key.noise) }
    }

    var volumeDb: Double {
        get {
            guard defaults.object(forKey: Key.volumeDb) != nil else { return NoiseEngine.defaultVolumeDb }
            return min(NoiseEngine.volumeMaxDb, max(NoiseEngine.volumeMinDb, defaults.double(forKey: Key.volumeDb)))
        }
        set { defaults.set(newValue, forKey: Key.volumeDb) }
    }

    var announce: Bool {
        get { defaults.object(forKey: Key.announce) == nil ? true : defaults.bool(forKey: Key.announce) }
        set { defaults.set(newValue, forKey: Key.announce) }
    }

    /// "#RRGGBB", or nil for the system accent color.
    var ballColor: String? {
        get {
            guard let value = defaults.string(forKey: Key.ballColor),
                  value.count == 7, value.hasPrefix("#") else { return nil }
            return value
        }
        set { defaults.set(newValue, forKey: Key.ballColor) }
    }
}
