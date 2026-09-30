import Foundation

// MARK: - Wand calibration: learn which hand landmark is the tip of the
// user's wand, so waves and motion track the tip instead of the palm.

/// Persisted wand-tip calibration, learned during the calibration flow.
struct WandCalibration: Codable {
    /// Landmark index (0...20, Vision 21-point order) of the wand tip.
    var tipIndex: Int
    /// Tip rest position (normalized, engine convention) at calibration time.
    var restX: Double
    var restY: Double
    /// Hand height at calibration time, for scale-invariant thresholds later.
    var scale: Double
    var calibratedAt: Date

    private static let key = "wandCalibration.v1"

    static func load() -> WandCalibration? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WandCalibration.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Friendly name for a landmark index, shown after calibration.
    static func landmarkName(_ i: Int) -> String {
        switch i {
        case 4: return "thumb tip"
        case 8: return "index fingertip"
        case 12: return "middle fingertip"
        case 16: return "ring fingertip"
        case 20: return "little fingertip"
        case 0: return "wrist"
        case 1, 2, 3: return "thumb"
        case 5, 6, 7: return "index finger"
        case 9, 10, 11: return "middle finger"
        case 13, 14, 15: return "ring finger"
        case 17, 18, 19: return "little finger"
        default: return "landmark \(i)"
        }
    }
}
