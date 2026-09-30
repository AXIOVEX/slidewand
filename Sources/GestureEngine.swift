import Foundation

// MARK: - Pure gesture logic (no Apple frameworks; ports the tested Python engine)

/// Normalized 2D point. Convention: x grows to the USER'S right (frame is
/// treated as mirrored), y grows downward (top-left origin).
struct Pt {
    var x: Double
    var y: Double
}

enum Gesture {
    case openPalm, fist, unknown
}

enum SwipeDir {
    case right, left
}

// MediaPipe/Vision 21-point hand order: wrist, then thumb/index/middle/ring/pinky.
private let tipPip: [(tip: Int, pip: Int)] = [(8, 6), (12, 10), (16, 14), (20, 18)]
private let palmIdx = [0, 5, 9, 13, 17]

private func dist(_ a: Pt, _ b: Pt) -> Double {
    return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
}

func fingerExtended(_ lm: [Pt], tip: Int, pip: Int, ratio: Double = 1.15) -> Bool {
    return dist(lm[tip], lm[0]) > ratio * ratio * dist(lm[pip], lm[0])
}

func classifyHand(_ lm: [Pt]) -> Gesture {
    let n = tipPip.filter { fingerExtended(lm, tip: $0.tip, pip: $0.pip) }.count
    if n >= 4 { return .openPalm }
    if n <= 1 { return .fist }
    return .unknown
}

func palmCentroid(_ lm: [Pt]) -> Pt {
    var sx = 0.0, sy = 0.0
    for i in palmIdx { sx += lm[i].x; sy += lm[i].y }
    let n = Double(palmIdx.count)
    return Pt(x: sx / n, y: sy / n)
}

func handHeight(_ lm: [Pt]) -> Double {
    let ys = lm.map { $0.y }
    return (ys.max() ?? 0) - (ys.min() ?? 0)
}

// MARK: - Swipe detector: fast horizontal hand motion in a sliding window

final class SwipeDetector {
    var minDx = 0.30
    let maxDy = 0.22
    let minDur = 0.10
    let maxDur = 0.55
    let minSpeed = 0.70
    let maxGap = 0.12

    private var samples: [(t: Double, x: Double, y: Double)] = []

    func reset() { samples.removeAll() }

    func update(t: Double, present: Bool, x: Double = 0, y: Double = 0) -> SwipeDir? {
        let cutoff = t - (maxDur + 0.15)
        samples.removeAll { $0.t < cutoff }
        guard present else { samples.removeAll(); return nil }
        samples.append((t, x, y))

        let n = samples.count
        for i in 0..<n {
            let s0 = samples[i]
            let dur = t - s0.t
            if dur > maxDur { continue }
            if dur < minDur { break } // samples are time-ordered
            var ok = true
            for j in (i + 1)..<n {
                if samples[j].t - samples[j - 1].t > maxGap { ok = false; break }
            }
            if !ok { continue }
            let dx = x - s0.x
            let dy = y - s0.y
            let adx = abs(dx), ady = abs(dy)
            if adx < minDx { continue }
            if ady > maxDy || ady > 0.75 * adx { continue }
            if adx / dur < minSpeed { continue }
            samples.removeAll()
            return dx > 0 ? .right : .left
        }
        return nil
    }
}

// MARK: - Hold detector: dwell on a steady open palm / fist

final class HoldDetector {
    var holdTime = 1.0
    let moveTol = 0.06

    private var gesture: Gesture?
    private var t0: Double = 0
    private var ax: Double = 0
    private var ay: Double = 0
    private var armed_ = false

    func reset() { gesture = nil }

    /// Returns (action, progress). Action is "NEXT"/"PREV"/nil; progress 0...1.
    func update(t: Double, present: Bool, gesture g: Gesture,
                x: Double = 0, y: Double = 0, armed: Bool = true) -> (String?, Double) {
        if !present || (g != .openPalm && g != .fist) {
            reset()
            return (nil, 0.0)
        }
        if gesture != g || hypot(x - ax, y - ay) > moveTol {
            gesture = g; t0 = t; ax = x; ay = y
            return (nil, 0.0)
        }
        let progress = min(1.0, (t - t0) / holdTime)
        if progress >= 1.0 {
            if !armed { return (nil, 1.0) } // hold it; fire when cooldown ends
            reset()
            return (g == .openPalm ? "NEXT" : "PREV", 1.0)
        }
        return (nil, progress)
    }
}

// MARK: - Trigger gate: one action per cooldown window

final class TriggerGate {
    var cooldown = 1.0
    private var last: Double = -1e9

    func ready(_ t: Double) -> Bool { return t - last >= cooldown }
    func fire(_ t: Double) { last = t }
}
