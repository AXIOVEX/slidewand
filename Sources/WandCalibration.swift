import Foundation

// MARK: - Wand profile: what the physical wand looks like, learned during
// the guided calibration flow (hold the top third in the box, tip up, then
// rotate left and back, right and back). Used to pick the wand out of the
// rectangle candidates each frame.

/// Persisted visual profile of the user's physical wand.
struct WandCalibration: Codable {
    /// Mean tip color, 0...1 RGB, sampled around the tip during calibration.
    var red: Double
    var green: Double
    var blue: Double
    /// Length/width shape ratio of the wand's rectangle.
    var aspect: Double
    var calibratedAt: Date

    private static let key = "wandProfile.v1"

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

    /// Euclidean distance between a candidate tip color and this profile.
    static func colorDistance(r: Double, g: Double, b: Double, to p: WandCalibration) -> Double {
        let dr = r - p.red, dg = g - p.green, db = b - p.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
