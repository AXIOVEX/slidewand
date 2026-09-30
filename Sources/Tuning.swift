import Foundation

// MARK: - Live tuning, persisted in UserDefaults. The engine re-reads these
// every frame, so the Preferences window applies instantly with no restart.

final class Tuning {
    static let shared = Tuning()

    private enum Key {
        static let swipeDistance = "swipeDistance"
        static let holdTime = "holdTime"
        static let cooldown = "cooldown"
        static let minHandSize = "minHandSize"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.swipeDistance: 0.30,
            Key.holdTime: 1.0,
            Key.cooldown: 1.0,
            Key.minHandSize: 0.16,
        ])
    }

    /// Minimum horizontal flick distance (fraction of frame width) that counts as a swipe.
    var swipeDistance: Double {
        get { defaults.double(forKey: Key.swipeDistance) }
        set { defaults.set(newValue, forKey: Key.swipeDistance) }
    }

    /// Seconds a palm/fist must be held still to trigger.
    var holdTime: Double {
        get { defaults.double(forKey: Key.holdTime) }
        set { defaults.set(newValue, forKey: Key.holdTime) }
    }

    /// Minimum seconds between slide changes.
    var cooldown: Double {
        get { defaults.double(forKey: Key.cooldown) }
        set { defaults.set(newValue, forKey: Key.cooldown) }
    }

    /// Minimum hand height (fraction of frame). Raise to ignore distant/background hands.
    var minHandSize: Double {
        get { defaults.double(forKey: Key.minHandSize) }
        set { defaults.set(newValue, forKey: Key.minHandSize) }
    }

    func restoreDefaults() {
        defaults.removeObject(forKey: Key.swipeDistance)
        defaults.removeObject(forKey: Key.holdTime)
        defaults.removeObject(forKey: Key.cooldown)
        defaults.removeObject(forKey: Key.minHandSize)
    }
}
