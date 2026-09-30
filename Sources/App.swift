import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import ServiceManagement

// MARK: - HUD state + overlay drawing

struct HudState {
    var points: [Pt]? = nil
    var trail: [Pt] = []
    var gesture: Gesture = .unknown
    var handOK: Bool = false
    var handFrac: Double = 0
    var holdProgress: Double = 0
    var fps: Double = 0
    var lastAction: String? = nil
    var lastActionAge: Double = 99
    var accessibilityOK: Bool = true
    var notice: String? = nil
    var wandTip: Pt? = nil
    var wandCorners: [Pt]? = nil
    var wandVisible: Bool = false
    var calibrating: Bool = false
    var calibrationProgress: Double = 0
    var calibrationHint: String = ""
    var calStep: Int = 0 // 0 idle, 1 find, 2 rotateLeft, 3 rotateRight
    var calBox: (x0: Double, y0: Double, x1: Double, y1: Double)? = nil
}

private let skeletonChains = [
    [0, 1, 2, 3, 4], [0, 5, 6, 7, 8], [0, 9, 10, 11, 12],
    [0, 13, 14, 15, 16], [0, 17, 18, 19, 20],
]

final class OverlayView: NSView {
    private var hud = HudState()

    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }

    func render(_ h: HudState) {
        hud = h
        needsDisplay = true
    }

    private func text(_ s: String, at p: CGPoint, size: CGFloat = 13,
                     color: NSColor = .white, bold: Bool = false) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (s as NSString).draw(at: p,
                             withAttributes: [.font: font, .foregroundColor: color])
    }

    /// Calibration progress bar; reads hud.calibrationProgress.
    private func drawCalProgress(at p: CGPoint, width: CGFloat) {
        NSColor.darkGray.setFill()
        NSBezierPath(roundedRect: NSRect(x: p.x, y: p.y, width: width, height: 12),
                     xRadius: 6, yRadius: 6).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(x: p.x, y: p.y,
                                         width: width * CGFloat(hud.calibrationProgress), height: 12),
                     xRadius: 6, yRadius: 6).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let vx: CGFloat = 10, vy: CGFloat = 10, vw: CGFloat = 640, vh: CGFloat = 480
        func X(_ u: Double) -> CGFloat { return vx + CGFloat(u) * vw }
        func Y(_ v: Double) -> CGFloat { return vy + CGFloat(v) * vh }

        // Top status bar
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(rect: NSRect(x: vx, y: vy, width: vw, height: 30)).fill()
        let gestureLabel: String
        switch hud.gesture {
        case .openPalm: gestureLabel = "OPEN PALM — hold for NEXT"
        case .fist: gestureLabel = "FIST — hold for PREV"
        case .unknown: gestureLabel = hud.handOK ? "wave quickly ← / →" : "show your hand to the camera"
        }
        text("SlideWand  |  \(gestureLabel)", at: CGPoint(x: vx + 10, y: vy + 7))
        let fpsStr = String(format: "%4.1f fps", hud.fps)
        (fpsStr as NSString).draw(at: CGPoint(x: vx + vw - 80, y: vy + 7),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 13),
                                                  .foregroundColor: NSColor.lightGray])

        // Hand skeleton + trail
        if let pts = hud.points, hud.handOK {
            NSColor.green.setStroke()
            for chain in skeletonChains {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: X(pts[chain[0]].x), y: Y(pts[chain[0]].y)))
                for i in chain.dropFirst() {
                    path.line(to: CGPoint(x: X(pts[i].x), y: Y(pts[i].y)))
                }
                path.lineWidth = 2
                path.stroke()
            }
            NSColor.green.setFill()
            for p in pts {
                NSBezierPath(ovalIn: NSRect(x: X(p.x) - 3, y: Y(p.y) - 3, width: 6, height: 6)).fill()
            }
        }
        // Physical wand: rectangle outline + tip marker (magenta). When the
        // wand is visible it drives the gestures, not the hand.
        if hud.wandVisible, let corners = hud.wandCorners, corners.count == 4 {
            NSColor.cyan.setStroke()
            let poly = NSBezierPath()
            poly.move(to: CGPoint(x: X(corners[0].x), y: Y(corners[0].y)))
            for c in corners.dropFirst() { poly.line(to: CGPoint(x: X(c.x), y: Y(c.y))) }
            poly.close()
            poly.lineWidth = 2
            poly.stroke()
            if let tip = hud.wandTip {
                NSColor.magenta.setFill()
                NSBezierPath(ovalIn: NSRect(x: X(tip.x) - 8, y: Y(tip.y) - 8,
                                            width: 16, height: 16)).fill()
                text("TIP", at: CGPoint(x: X(tip.x) + 13, y: Y(tip.y) - 16), size: 11,
                     color: .magenta, bold: true)
            }
        }
        if hud.trail.count > 1 {
            for i in 1..<hud.trail.count {
                let a = CGFloat(i) / CGFloat(hud.trail.count)
                NSColor(red: 1.0 * a, green: 0.8 * a, blue: 0, alpha: 0.9).setStroke()
                let path = NSBezierPath()
                path.move(to: CGPoint(x: X(hud.trail[i - 1].x), y: Y(hud.trail[i - 1].y)))
                path.line(to: CGPoint(x: X(hud.trail[i].x), y: Y(hud.trail[i].y)))
                path.lineWidth = 3
                path.stroke()
            }
        }

        // Calibration guidance overlay: per-step instructions on the video
        if hud.calibrating {
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: NSRect(x: vx, y: vy, width: vw, height: vh)).fill()

            if hud.calStep == 1, let box = hud.calBox {
                // Step 1: target box in the top third — hold the wand in here, tip up
                let bx = vx + CGFloat(box.x0) * vw, byTop = vy + (1 - CGFloat(box.y0)) * vh
                let bw = CGFloat(box.x1 - box.x0) * vw, bh = CGFloat(box.y1 - box.y0) * vh
                let by = byTop - bh
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let rect = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh),
                                        xRadius: 14, yRadius: 14)
                rect.lineWidth = 2.5
                rect.setLineDash([10, 7], count: 2, phase: 0)
                rect.stroke()
                // Up arrow: tip points up
                let ax = bx + bw / 2
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let arrow = NSBezierPath()
                arrow.move(to: CGPoint(x: ax, y: by + 50))
                arrow.line(to: CGPoint(x: ax, y: by + 130))
                arrow.move(to: CGPoint(x: ax - 16, y: by + 108))
                arrow.line(to: CGPoint(x: ax, y: by + 132))
                arrow.line(to: CGPoint(x: ax + 16, y: by + 108))
                arrow.lineWidth = 4
                arrow.lineCapStyle = .round
                arrow.stroke()
                text("TIP UP", at: CGPoint(x: ax - 32, y: by + 22), size: 15,
                     color: .white, bold: true)
                text(hud.calibrationHint, at: CGPoint(x: vx + 20, y: vy + vh - 30),
                     size: 14, color: .white, bold: true)
                drawCalProgress(at: CGPoint(x: vx + 20, y: vy + vh - 58), width: vw - 40)
            } else if hud.calStep == 2 || hud.calStep == 3 {
                // Steps 2/3: rotation direction arrow
                let cx = vx + vw / 2, cy = vy + vh / 2 + 40
                let dir: CGFloat = hud.calStep == 2 ? -1 : 1
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let arrow = NSBezierPath()
                arrow.move(to: CGPoint(x: cx - dir * 90, y: cy))
                arrow.line(to: CGPoint(x: cx + dir * 90, y: cy))
                arrow.move(to: CGPoint(x: cx + dir * 90 - dir * 22, y: cy + 16))
                arrow.line(to: CGPoint(x: cx + dir * 90, y: cy))
                arrow.line(to: CGPoint(x: cx + dir * 90 - dir * 22, y: cy - 16))
                arrow.lineWidth = 5
                arrow.lineCapStyle = .round
                arrow.stroke()
                text(hud.calibrationHint, at: CGPoint(x: vx + 20, y: cy + 60),
                     size: 15, color: .white, bold: true)
                text("Keep the tip in view while you tilt.", at: CGPoint(x: vx + 20, y: cy + 36),
                     size: 12, color: .lightGray)
                drawCalProgress(at: CGPoint(x: vx + 20, y: cy - 60), width: vw - 40)
            }

            // Live tip dot in every step: what the app thinks the tip is
            if let tip = hud.wandTip, hud.wandVisible {
                NSColor.yellow.setFill()
                NSBezierPath(ovalIn: NSRect(x: X(tip.x) - 9, y: Y(tip.y) - 9,
                                            width: 18, height: 18)).fill()
            }
        }

        // Distance meter ("too far" hint)
        text("distance", at: CGPoint(x: vx + 10, y: vy + 40), size: 11, color: .lightGray)
        NSColor.darkGray.setFill()
        NSBezierPath(rect: NSRect(x: vx + 10, y: vy + 56, width: 150, height: 10)).fill()
        let fillW = 150 * min(1.0, CGFloat(hud.handFrac) / 0.6)
        (hud.handOK ? NSColor.green : NSColor.orange).setFill()
        NSBezierPath(rect: NSRect(x: vx + 10, y: vy + 56, width: fillW, height: 10)).fill()

        // Hold progress ring
        if hud.holdProgress > 0.01 {
            let c = CGPoint(x: vx + vw - 40, y: vy + 66)
            NSColor.darkGray.setStroke()
            let bg = NSBezierPath()
            bg.appendArc(withCenter: c, radius: 20, startAngle: 0, endAngle: 360)
            bg.lineWidth = 5
            bg.stroke()
            NSColor.green.setStroke()
            let fg = NSBezierPath()
            fg.appendArc(withCenter: c, radius: 20,
                         startAngle: -90, endAngle: -90 + 360 * CGFloat(hud.holdProgress),
                         clockwise: false)
            fg.lineWidth = 5
            fg.stroke()
        }

        // Action flash
        if let action = hud.lastAction, hud.lastActionAge < 0.9 {
            let s = action == "NEXT" ? "NEXT SLIDE  →" : "←  PREV SLIDE"
            let attrs: [NSAttributedString.Key: Any] =
                [.font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.green]
            let size = (s as NSString).size(withAttributes: attrs)
            let r = NSRect(x: vx + (vw - size.width) / 2 - 14, y: vy + vh / 2 - 30,
                           width: size.width + 28, height: size.height + 16)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(rect: r).fill()
            (s as NSString).draw(at: CGPoint(x: r.minX + 14, y: r.minY + 8), withAttributes: attrs)
        }

        // Camera notice (denied / error / waiting)
        if let notice = hud.notice {
            let attrs: [NSAttributedString.Key: Any] =
                [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white]
            let size = (notice as NSString).size(withAttributes: attrs)
            let r = NSRect(x: vx + (vw - size.width) / 2 - 16, y: vy + vh / 2 - 24,
                           width: size.width + 32, height: size.height + 16)
            NSColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 0.92).setFill()
            NSBezierPath(rect: r).fill()
            (notice as NSString).draw(at: CGPoint(x: r.minX + 16, y: r.minY + 8), withAttributes: attrs)
        }

        // Accessibility warning
        if !hud.accessibilityOK {
            NSColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 0.95).setFill()
            NSBezierPath(rect: NSRect(x: vx, y: vy + vh - 30, width: vw, height: 30)).fill()
            text("KEYS BLOCKED — grant Accessibility (System Settings), then it just works",
                 at: CGPoint(x: vx + 10, y: vy + vh - 23), size: 13, bold: true)
        }

        // Legend below the video
        text("wave → : next    wave ← : prev    hold open palm 1s : next    hold fist 1s : prev",
             at: CGPoint(x: vx + 10, y: vy + vh + 14), size: 12, color: .lightGray)
    }
}

// MARK: - Mirrored camera preview

final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        // Mirror the displayed video horizontally (selfie-style) with a pure
        // Core Animation transform. This is display-only: the gesture engine
        // already flips Vision x-coordinates (see VisionHandTracker), so the
        // hand overlay and wave directions line up with the mirrored image.
        previewLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        previewLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // NOTE (v1.3.2/v1.3.3): do NOT touch previewLayer.connection's
    // mirroring/rotation properties. On macOS 26's Tundra capture stack,
    // setting isVideoMirrored throws an ObjC exception (via
    // isVideoRotationAngleSupported:) which AppKit turns into a SIGTRAP crash.
    // The CALayer transform above mirrors the preview without ever talking
    // to the capture connection.
    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

// MARK: - Controller: engine loop + public state for the test window / menu

final class WandController: NSObject, HandTrackerDelegate {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 560))

    // Diagnostics surfaced to the test window and status menu.
    var cameraRunning = false
    var cameraError: String? = nil
    var accessibilityOK = true
    var gestureLabel = "starting…"
    var fps: Double = 0
    var nextCount = 0
    var prevCount = 0
    var lastAction: String? = nil
    var lastActionT: Double = 0
    var eventLog: [(Date, String)] = []
    var notice: String? = nil

    private let tracker = VisionHandTracker()
    private let preview: PreviewView
    private let overlay = OverlayView()

    private let swipe = SwipeDetector()
    private let hold = HoldDetector()
    private let gate = TriggerGate()
    private var trail: [Pt] = []

    private var fpsEma = 30.0
    private var prevT = ProcessInfo.processInfo.systemUptime

    private var axPrompted = false
    private var lastAxCheck: Double = 0

    // Physical wand tracking: the stick, not the hand. Rectangle detection
    // finds wand candidates each frame; the tracked tip drives gestures.
    var calibration: WandCalibration? = WandCalibration.load()
    var calibrationMessage: String? = nil
    var wandTip: Pt? = nil          // smoothed tip; nil when the wand isn't seen
    var wandVisible = false
    private var wandSmooth: Pt? = nil
    private var wandLastSeen: Double = 0
    private var lastWandCandidate: WandCandidate? = nil
    private var wasWandDriven = false

    // Guided calibration steps: find the wand, rotate left, rotate right.
    enum WandCalStep { case idle, find, rotateLeft, rotateRight }
    var calStep: WandCalStep = .idle
    var calibrating: Bool { calStep != .idle }
    private var stepStart: Double = 0
    private var stepFrames = 0
    private var stepVisible = 0
    private var stepAnchor: Pt? = nil
    private var stepMinX = Double.greatestFiniteMagnitude
    private var stepMaxX = -Double.greatestFiniteMagnitude
    private var profileR = 0.0, profileG = 0.0, profileB = 0.0
    private var profileAspect = 0.0, profileN = 0.0
    private var findStable: [(Pt, Double)] = []

    /// Target box for calibration step 1 (normalized, top-left origin):
    /// the top third of the frame, centered.
    private let calBox = (x0: 0.32, y0: 0.06, x1: 0.68, y1: 0.42)
    private func calBoxContains(_ p: Pt) -> Bool {
        p.x >= calBox.x0 && p.x <= calBox.x1 && p.y >= calBox.y0 && p.y <= calBox.y1
    }

    private var minHandSize: Double { Tuning.shared.minHandSize }

    override init() {
        preview = PreviewView(session: tracker.captureSession)
        super.init()
        preview.frame = NSRect(x: 10, y: 70, width: 640, height: 480)
        preview.autoresizingMask = [.width, .height]
        overlay.frame = NSRect(x: 0, y: 0, width: 660, height: 560)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(preview)
        view.addSubview(overlay)
        accessibilityOK = KeySender.accessibilityTrusted()
        render(points: nil) // draw immediately — don't wait for the first camera frame
    }

    func start() {
        tracker.delegate = self
        do {
            try tracker.start()
            cameraRunning = true
            cameraError = nil
            notice = nil
        } catch {
            cameraRunning = false
            cameraError = (error as NSError).localizedDescription
            notice = cameraError
        }
        render(points: nil)
    }

    func showCameraDenied() {
        cameraRunning = false
        notice = "Camera access denied — enable it in System Settings → Privacy & Security → Camera."
        render(points: nil)
    }

    /// Called on quit: release the camera promptly.
    func stop() {
        tracker.stop()
        cameraRunning = false
    }

    // MARK: Wand calibration (physical wand)

    var calibrationProgress: Double {
        let now = ProcessInfo.processInfo.systemUptime
        switch calStep {
        case .idle: return 0
        case .find:
            guard let first = findStable.first else { return 0 }
            return min(1.0, (now - first.1) / 1.2)
        case .rotateLeft, .rotateRight:
            return min(1.0, (now - stepStart) / 3.0)
        }
    }

    /// Begin the guided calibration: find the wand, rotate left, rotate right.
    func startCalibration() {
        calStep = .find
        calibrationMessage = nil
        findStable.removeAll()
        resetProfileAcc()
        gestureLabel = "calibrating — follow the steps…"
        swipe.reset(); hold.reset(); trail.removeAll()
    }

    /// Live hint for the calibration window + preview overlay.
    var calibrationHint: String {
        switch calStep {
        case .idle: return ""
        case .find:
            if let tip = wandTip, wandVisible, calBoxContains(tip) { return "Hold still…" }
            return "Hold the TOP THIRD of your wand in the box, tip pointing UP"
        case .rotateLeft:
            return stepMinX < (stepAnchor?.x ?? 1) - 0.08
                ? "Good — bring it back to center…"
                : "Slowly tilt the wand LEFT… then back to center"
        case .rotateRight:
            return stepMaxX > (stepAnchor?.x ?? 0) + 0.08
                ? "Good — bring it back to center…"
                : "Slowly tilt the wand RIGHT… then back to center"
        }
    }

    var calibrationStepTitle: String {
        switch calStep {
        case .idle: return "Calibrate Wand"
        case .find: return "Step 1 of 3 — Show your wand"
        case .rotateLeft: return "Step 2 of 3 — Rotate left"
        case .rotateRight: return "Step 3 of 3 — Rotate right"
        }
    }

    func cancelCalibration() {
        calStep = .idle
        gestureLabel = "wave quickly ← / →"
    }

    func clearCalibration() {
        WandCalibration.clear()
        calibration = nil
        calibrationMessage = nil
    }

    private func resetProfileAcc() {
        profileR = 0; profileG = 0; profileB = 0; profileAspect = 0; profileN = 0
    }

    private func beginRotateStep(_ step: WandCalStep, now: Double) {
        calStep = step
        stepStart = now
        stepFrames = 0
        stepVisible = 0
        stepAnchor = wandTip
        stepMinX = Double.greatestFiniteMagnitude
        stepMaxX = -Double.greatestFiniteMagnitude
    }

    /// Called every frame while calibrating. Accumulates the tip's color and
    /// shape profile and advances the guided steps.
    private func updateWandCalibration(now: Double) {
        stepFrames += 1
        if wandVisible, let cand = lastWandCandidate {
            stepVisible += 1
            profileR += cand.tipColor.r; profileG += cand.tipColor.g
            profileB += cand.tipColor.b; profileAspect += cand.aspect
            profileN += 1
        }
        switch calStep {
        case .idle:
            break
        case .find:
            if let tip = wandTip, wandVisible, calBoxContains(tip) {
                findStable.append((tip, now))
                findStable.removeAll { now - $0.1 > 1.2 }
                if let first = findStable.first, now - first.1 >= 1.2 {
                    let xs = findStable.map { $0.0.x }, ys = findStable.map { $0.0.y }
                    let wander = (xs.max() ?? 0) - (xs.min() ?? 0) + (ys.max() ?? 0) - (ys.min() ?? 0)
                    if wander < 0.08 { beginRotateStep(.rotateLeft, now: now) }
                }
            } else {
                findStable.removeAll()
            }
        case .rotateLeft, .rotateRight:
            if let tip = wandTip, wandVisible {
                stepMinX = min(stepMinX, tip.x)
                stepMaxX = max(stepMaxX, tip.x)
            }
            if now - stepStart >= 3.0 {
                let vis = Double(stepVisible) / Double(max(stepFrames, 1))
                if vis >= 0.5 {
                    if calStep == .rotateLeft {
                        beginRotateStep(.rotateRight, now: now)
                    } else {
                        finishWandCalibration()
                    }
                } else {
                    // Lost the wand mid-step — retry the step, keep the profile so far.
                    calibrationMessage = "I lost sight of the wand — let's try that step again."
                    beginRotateStep(calStep, now: now)
                }
            }
        }
    }

    private func finishWandCalibration() {
        let n = max(profileN, 1)
        let cal = WandCalibration(red: profileR / n, green: profileG / n,
                                  blue: profileB / n, aspect: profileAspect / n,
                                  calibratedAt: Date())
        cal.save()
        calibration = cal
        calStep = .idle
        calibrationMessage = "Wand learned ✓ — wave the tip ← / → to change slides."
        gestureLabel = "wave quickly ← / →"
    }

    // MARK: Physical wand tracking

    /// Pick the wand candidate each frame and smooth the tip.
    private func updateWandTracking(wands: [WandCandidate], now: Double) {
        var pick: WandCandidate? = nil
        if calStep == .find {
            // Step 1: only a tip inside the target box counts.
            pick = wands.filter { calBoxContains($0.tip) }.max(by: { $0.length < $1.length })
        } else {
            var scored = wands
            if let prof = calibration {
                scored = scored.filter {
                    WandCalibration.colorDistance(r: $0.tipColor.r, g: $0.tipColor.g,
                                                 b: $0.tipColor.b, to: prof) < 0.4
                }
            }
            if let s = wandSmooth {
                pick = scored.min(by: {
                    hypot($0.tip.x - s.x, $0.tip.y - s.y) < hypot($1.tip.x - s.x, $1.tip.y - s.y)
                })
                if let p = pick, hypot(p.tip.x - s.x, p.tip.y - s.y) > 0.3 { pick = nil }
            } else {
                pick = scored.max(by: { $0.length < $1.length })
            }
        }
        if let p = pick {
            if let s = wandSmooth {
                wandSmooth = Pt(x: s.x + 0.45 * (p.tip.x - s.x),
                                y: s.y + 0.45 * (p.tip.y - s.y))
            } else {
                wandSmooth = p.tip
            }
            wandTip = wandSmooth
            wandLastSeen = now
            wandVisible = true
            lastWandCandidate = p
        } else {
            wandVisible = (now - wandLastSeen) < 0.4
            if !wandVisible { wandTip = nil; wandSmooth = nil; lastWandCandidate = nil }
        }
    }

    func refreshHUD() {
        render(points: nil)
    }

    // MARK: HandTrackerDelegate (main thread)

    func handTracker(_ tracker: VisionHandTracker, didUpdate points: [Pt]?, wands: [WandCandidate]) {
        let now = ProcessInfo.processInfo.systemUptime

        // Live tuning from the Preferences window — synced every frame, no restart needed.
        swipe.minDx = Tuning.shared.swipeDistance
        hold.holdTime = Tuning.shared.holdTime
        gate.cooldown = Tuning.shared.cooldown

        let dt = now - prevT
        prevT = now
        if dt > 0 { fpsEma = 0.9 * fpsEma + 0.1 * (1.0 / dt) }
        fps = fpsEma

        // Accessibility is re-checked periodically; macOS never prompts, so we
        // open the Settings page once and show a banner until granted.
        if now - lastAxCheck > 2.0 {
            lastAxCheck = now
            accessibilityOK = KeySender.accessibilityTrusted()
            if !accessibilityOK && !axPrompted {
                axPrompted = true
                KeySender.openAccessibilitySettings()
            }
        }

        var gesture: Gesture = .unknown
        var cx = 0.0, cy = 0.0
        let handOK = points.map { handHeight($0) >= minHandSize } ?? false
        updateWandTracking(wands: wands, now: now)
        if calibrating {
            // Learning the physical wand — gesture detection is paused meanwhile.
            updateWandCalibration(now: now)
            render(points: points, handOK: handOK)
            return
        }
        // The wand tip drives gestures whenever it's visible; the palm is the
        // fallback when there's no wand in view. Never track hands as wands.
        let wandDriven = wandVisible && wandTip != nil
        if wandDriven != wasWandDriven { trail.removeAll(); wasWandDriven = wandDriven }
        let trackPt: Pt?
        if wandDriven, let wt = wandTip {
            trackPt = wt
        } else if let pts = points, handOK {
            trackPt = palmCentroid(pts)
        } else {
            trackPt = nil
        }
        let present = trackPt != nil
        if let tp = trackPt {
            cx = tp.x; cy = tp.y
            if let pts = points, handOK { gesture = classifyHand(pts) }
            trail.append(Pt(x: cx, y: cy))
            if trail.count > 24 { trail.removeFirst() }
        }
        switch gesture {
        case .openPalm: gestureLabel = "OPEN PALM — hold for NEXT"
        case .fist: gestureLabel = "FIST — hold for PREV"
        case .unknown:
            gestureLabel = wandDriven ? "wave the wand tip ← / →"
                : (handOK ? "wave quickly ← / →" : "show your hand to the camera")
        }

        var action: String? = nil
        var source = ""
        let dir: SwipeDir? = present
            ? swipe.update(t: now, present: true, x: cx, y: cy)
            : swipe.update(t: now, present: false)
        if let dir = dir, gate.ready(now) {
            action = (dir == .right) ? "NEXT" : "PREV"
            source = dir == .right ? "swipe right" : "swipe left"
            gate.fire(now)
            swipe.reset()
            hold.reset()
        } else if dir != nil {
            swipe.reset() // swallowed by cooldown; don't queue it
        }

        var progress = 0.0
        if action == nil, present {
            let (fired, p) = hold.update(t: now, present: true, gesture: gesture,
                                        x: cx, y: cy, armed: gate.ready(now))
            progress = p
            if let fired = fired, gate.ready(now) {
                action = fired
                source = fired == "NEXT" ? "hold palm" : "hold fist"
                gate.fire(now)
                swipe.reset()
            }
        } else if !present {
            progress = hold.update(t: now, present: false, gesture: .unknown,
                                   armed: gate.ready(now)).1
        }

        if let action = action {
            lastAction = action
            lastActionT = now
            if action == "NEXT" { nextCount += 1 } else { prevCount += 1 }
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            eventLog.append((Date(), "\(fmt.string(from: Date()))  \(source) → \(action)"))
            if eventLog.count > 60 { eventLog.removeFirst(eventLog.count - 60) }
            KeySender.press(action == "NEXT" ? KeySender.keyNext : KeySender.keyPrev)
        }

        render(points: points, gesture: gesture, handOK: handOK,
               progress: progress, actionAge: now - lastActionT)
    }

    private func render(points: [Pt]?, gesture: Gesture = .unknown,
                       handOK: Bool = false, progress: Double = 0,
                       actionAge: Double = 99) {
        var hud = HudState()
        hud.points = points
        hud.trail = trail
        hud.gesture = gesture
        hud.handOK = handOK
        hud.handFrac = points.map { handHeight($0) } ?? 0
        hud.holdProgress = progress
        hud.fps = fpsEma
        hud.lastAction = lastAction
        hud.lastActionAge = actionAge
        hud.accessibilityOK = accessibilityOK
        hud.notice = notice
        hud.wandTip = wandVisible ? wandTip : nil
        hud.wandCorners = wandVisible ? lastWandCandidate?.corners : nil
        hud.wandVisible = wandVisible
        hud.calibrating = calibrating
        hud.calibrationProgress = calibrationProgress
        hud.calibrationHint = calibrationHint
        hud.calStep = calStep == .find ? 1 : calStep == .rotateLeft ? 2 : calStep == .rotateRight ? 3 : 0
        hud.calBox = (calBox.x0, calBox.y0, calBox.x1, calBox.y1)
        overlay.render(hud)
    }
}

// MARK: - Gesture test window

final class TestWindowController: NSWindowController {
    private weak var wand: WandController?
    private var timer: Timer?
    private var lastSeenLogCount = -1

    private let stateLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let logView = NSTextView()

    init(wand: WandController) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered,
                           defer: false)
        super.init(window: win)
        self.wand = wand
        win.title = "SlideWand — Gesture Test"
        win.isReleasedWhenClosed = false

        let content = win.contentView!

        stateLabel.frame = NSRect(x: 20, y: 322, width: 400, height: 52)
        stateLabel.font = NSFont.boldSystemFont(ofSize: 28)
        stateLabel.alignment = .center
        content.addSubview(stateLabel)

        countLabel.frame = NSRect(x: 20, y: 294, width: 400, height: 22)
        countLabel.font = NSFont.systemFont(ofSize: 13)
        countLabel.alignment = .center
        countLabel.textColor = .secondaryLabelColor
        content.addSubview(countLabel)

        statusLabel.frame = NSRect(x: 20, y: 270, width: 400, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .center
        content.addSubview(statusLabel)

        let logTitle = NSTextField(labelWithString: "Event log — triggers send real arrow keys to the front app:")
        logTitle.frame = NSRect(x: 20, y: 248, width: 400, height: 16)
        logTitle.font = NSFont.systemFont(ofSize: 11)
        logTitle.textColor = .secondaryLabelColor
        content.addSubview(logTitle)

        logView.frame = NSRect(x: 0, y: 0, width: 400, height: 220)
        logView.isEditable = false
        logView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 400, height: 222))
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        content.addSubview(scroll)

        logView.string = """
            Wave right / left — or hold an open palm / fist for 1s.
            Each trigger below also pressed a real arrow key.
            ————————————————————————————————
            """
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastSeenLogCount = -1
        if timer == nil {
            timer = Timer.scheduledTimer(timeInterval: 0.25, target: self,
                                         selector: #selector(tick),
                                         userInfo: nil, repeats: true)
        }
        tick()
    }

    @objc private func tick() {
        guard let win = window, win.isVisible, let wand = wand else {
            timer?.invalidate()
            timer = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let age = now - wand.lastActionT
        if let a = wand.lastAction, age < 1.2 {
            stateLabel.stringValue = a == "NEXT" ? "NEXT  →" : "←  PREV"
            stateLabel.textColor = .systemGreen
        } else {
            stateLabel.stringValue = wand.gestureLabel
            stateLabel.textColor = .labelColor
        }
        countLabel.stringValue =
            "Next: \(wand.nextCount)    Prev: \(wand.prevCount)    \(String(format: "%.0f", wand.fps)) fps"

        var statusParts: [String] = []
        if wand.cameraRunning {
            statusParts.append("Camera: ON")
        } else if wand.cameraError != nil {
            statusParts.append("Camera: OFF")
        } else {
            statusParts.append("Camera: starting…")
        }
        statusParts.append(wand.accessibilityOK ? "Accessibility: granted" : "Accessibility: BLOCKED — keys won't send")
        if wand.calibration != nil {
            statusParts.append("Wand: profile learned ✓")
        } else {
            statusParts.append("Wand: not calibrated")
        }
        if wand.wandVisible {
            statusParts.append("Wand tip: visible")
        }
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let bld = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        statusParts.append("v\(ver) (\(bld))")
        statusLabel.stringValue = statusParts.joined(separator: "   ·   ")
        statusLabel.textColor = (!wand.cameraRunning || !wand.accessibilityOK) ? .systemRed : .systemGreen

        if wand.eventLog.count != lastSeenLogCount {
            lastSeenLogCount = wand.eventLog.count
            var s = logView.string
            // Rebuild from the stored hint + events to stay in sync.
            let hintEnd = s.range(of: "———")?.upperBound
            let hint = hintEnd.map { String(s[..<$0]) + "\n" } ?? ""
            s = hint + wand.eventLog.map { $0.1 }.joined(separator: "\n")
            if !wand.eventLog.isEmpty { s += "\n" }
            logView.string = s
            logView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - Wand calibration window: teach SlideWand your physical wand

final class CalibrationWindowController: NSWindowController {
    private weak var wand: WandController?
    private var timer: Timer?

    private let stepLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let startButton = NSButton(title: "Start Calibration", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    init(wand: WandController) {
        self.wand = wand
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Calibrate Wand"
        win.center()
        super.init(window: win)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
        win.contentView = view

        let title = NSTextField(labelWithString: "Teach SlideWand your wand")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 20, y: 268, width: 400, height: 22)
        view.addSubview(title)

        let help = NSTextField(wrappingLabelWithString:
            "SlideWand tracks your physical wand — the stick itself, not your hand. " +
            "The guided steps photograph the tip to learn its shape and color, " +
            "then watch you rotate it so tracking stays locked while it moves. " +
            "Watch the camera preview while you do it.")
        help.frame = NSRect(x: 20, y: 188, width: 400, height: 74)
        view.addSubview(help)

        stepLabel.frame = NSRect(x: 20, y: 160, width: 400, height: 22)
        stepLabel.font = .boldSystemFont(ofSize: 13)
        view.addSubview(stepLabel)

        progress.frame = NSRect(x: 20, y: 132, width: 400, height: 16)
        progress.minValue = 0; progress.maxValue = 1
        progress.isIndeterminate = false
        progress.doubleValue = 0
        view.addSubview(progress)

        statusLabel.frame = NSRect(x: 20, y: 100, width: 400, height: 24)
        statusLabel.font = .systemFont(ofSize: 13)
        view.addSubview(statusLabel)

        startButton.frame = NSRect(x: 20, y: 20, width: 170, height: 32)
        startButton.bezelStyle = .rounded
        startButton.target = self; startButton.action = #selector(startPressed)
        view.addSubview(startButton)

        clearButton.frame = NSRect(x: 200, y: 20, width: 100, height: 32)
        clearButton.bezelStyle = .rounded
        clearButton.target = self; clearButton.action = #selector(clearPressed)
        view.addSubview(clearButton)

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        timer?.invalidate()
        wand?.cancelCalibration()
    }

    @objc private func startPressed() {
        wand?.startCalibration()
    }

    @objc private func clearPressed() {
        wand?.clearCalibration()
        refresh()
    }

    private func refresh() {
        guard let wand = wand else { return }
        if wand.calibrating {
            stepLabel.stringValue = wand.calibrationStepTitle
            progress.doubleValue = wand.calibrationProgress
            statusLabel.stringValue = wand.calibrationHint
            statusLabel.textColor = .labelColor
            startButton.isEnabled = false
        } else {
            stepLabel.stringValue = ""
            progress.doubleValue = wand.calibration != nil ? 1.0 : 0
            startButton.isEnabled = true
            if let msg = wand.calibrationMessage {
                statusLabel.stringValue = msg
                statusLabel.textColor = wand.calibration != nil ? .systemGreen : .systemOrange
                // Keep the message until the next calibration run.
            } else if let cal = wand.calibration {
                let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
                statusLabel.stringValue =
                    "Calibrated \(fmt.string(from: cal.calibratedAt)) — tracking your wand tip."
                statusLabel.textColor = .systemGreen
            } else {
                statusLabel.stringValue = "Not calibrated — waves track the palm until a wand is learned."
                statusLabel.textColor = .secondaryLabelColor
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preferences window: tuning sliders + launch at login

final class PreferencesWindowController: NSWindowController {
    private struct Row {
        let title: String
        let min: Double
        let max: Double
        let format: (Double) -> String
        let get: () -> Double
        let set: (Double) -> Void
    }

    private var rows: [Row] = []
    private var sliders: [NSSlider] = []
    private var valueLabels: [NSTextField] = []
    private var loginCheckbox: NSButton!

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        super.init(window: win)
        win.title = "SlideWand Preferences"
        win.isReleasedWhenClosed = false

        rows = [
            Row(title: "Swipe distance", min: 0.15, max: 0.45,
                format: { String(format: "%.2f", $0) },
                get: { Tuning.shared.swipeDistance },
                set: { Tuning.shared.swipeDistance = $0 }),
            Row(title: "Hold time", min: 0.5, max: 2.0,
                format: { String(format: "%.1fs", $0) },
                get: { Tuning.shared.holdTime },
                set: { Tuning.shared.holdTime = $0 }),
            Row(title: "Cooldown", min: 0.5, max: 2.0,
                format: { String(format: "%.1fs", $0) },
                get: { Tuning.shared.cooldown },
                set: { Tuning.shared.cooldown = $0 }),
            Row(title: "Min hand size", min: 0.08, max: 0.30,
                format: { String(format: "%.2f", $0) },
                get: { Tuning.shared.minHandSize },
                set: { Tuning.shared.minHandSize = $0 }),
        ]

        let content = win.contentView!
        var y: CGFloat = 300
        for (i, row) in rows.enumerated() {
            let title = NSTextField(labelWithString: row.title)
            title.frame = NSRect(x: 20, y: y, width: 130, height: 20)
            title.font = NSFont.systemFont(ofSize: 13)
            content.addSubview(title)

            let slider = NSSlider(value: row.get(), minValue: row.min, maxValue: row.max,
                                  target: self, action: #selector(sliderChanged(_:)))
            slider.frame = NSRect(x: 150, y: y - 2, width: 170, height: 24)
            slider.tag = i
            content.addSubview(slider)
            sliders.append(slider)

            let val = NSTextField(labelWithString: row.format(row.get()))
            val.frame = NSRect(x: 326, y: y, width: 74, height: 20)
            val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            content.addSubview(val)
            valueLabels.append(val)

            y -= 44
        }

        loginCheckbox = NSButton(checkboxWithTitle: "Open SlideWand at login",
                                 target: self, action: #selector(loginToggled(_:)))
        loginCheckbox.frame = NSRect(x: 20, y: 84, width: 380, height: 20)
        content.addSubview(loginCheckbox)

        let restore = NSButton(title: "Restore Defaults", target: self,
                               action: #selector(restoreDefaults(_:)))
        restore.frame = NSRect(x: 20, y: 44, width: 140, height: 28)
        restore.bezelStyle = .rounded
        content.addSubview(restore)

        let hint = NSTextField(labelWithString: "Changes apply immediately — no restart needed.")
        hint.frame = NSRect(x: 20, y: 16, width: 380, height: 16)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)

        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        for (i, row) in rows.enumerated() {
            sliders[i].doubleValue = row.get()
            valueLabels[i].stringValue = row.format(row.get())
        }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let row = rows[sender.tag]
        let v = (sender.doubleValue * 100).rounded() / 100
        row.set(v)
        valueLabels[sender.tag].stringValue = row.format(v)
    }

    @objc private func loginToggled(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Fall through; the checkbox is reset to reality below.
        }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func restoreDefaults(_ sender: NSButton) {
        Tuning.shared.restoreDefaults()
        refresh()
    }
}

// MARK: - App bootstrap: menu-bar app + preview window + test window
// NOTE: entry point is Sources/main.swift (explicit delegate wiring).

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLineItem: NSMenuItem!
    private var previewToggleItems: [NSMenuItem] = []
    private var previewWindow: NSWindow!
    private var controller: WandController!
    private var testController: TestWindowController!
    private var prefsController: PreferencesWindowController!
    private var calibrateController: CalibrationWindowController!
    private var transientStatus: String? = nil
    private var menuTimer: Timer?
    private var tickCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[SlideWand] didFinishLaunching ENTER")
        Log.reset()
        print("[SlideWand] log path: \(Log.url.path)")
        Log.line("didFinishLaunching: start (v0.2.0)")
        print("[SlideWand] log exists after write: \(FileManager.default.fileExists(atPath: Log.url.path))")
        // NOTE: no setActivationPolicy call — this is a regular Dock app
        // (LSUIElement was removed in v1.3.0; on macOS 26 it parked the
        // status item and windows invisibly). The extra call hid all windows
        // on some systems.
        buildStatusItem()
        buildMainMenu()
        Log.line("status item built")
        print("[SlideWand] status item built")

        controller = WandController()
        Log.line("WandController created")
        print("[SlideWand] WandController created")
        testController = TestWindowController(wand: controller)
        prefsController = PreferencesWindowController()
        calibrateController = CalibrationWindowController(wand: controller)
        Log.line("test + prefs controllers created")

        previewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                                styleMask: [.titled, .closable, .miniaturizable],
                                backing: .buffered,
                                defer: false)
        previewWindow.title = "SlideWand — camera preview"
        previewWindow.center()
        previewWindow.contentView = controller.view
        previewWindow.makeKeyAndOrderFront(nil)
        // Regular (Dock) app: make sure we're actually frontmost on launch so
        // the preview window can't end up behind other apps or unpainted.
        NSApp.activate(ignoringOtherApps: true)
        Log.line("preview shown: isVisible=\(previewWindow.isVisible) appWindows=\(NSApp.windows.count) active=\(NSApp.isActive)")
        print("[SlideWand] preview shown: isVisible=\(previewWindow.isVisible) windows=\(NSApp.windows.count) active=\(NSApp.isActive)")

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        Log.line("camera auth status: \(authStatus.rawValue)")
        print("[SlideWand] camera auth status: \(authStatus.rawValue)")
        switch authStatus {
        case .authorized:
            controller.start()
        case .notDetermined:
            controller.notice = "Waiting for camera permission…"
            controller.refreshHUD()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.controller.start()
                    } else {
                        self.controller.showCameraDenied()
                    }
                }
            }
        case .denied, .restricted:
            controller.showCameraDenied()
        @unknown default:
            controller.showCameraDenied()
        }

        menuTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                         selector: #selector(updateMenu),
                                         userInfo: nil, repeats: true)
        updateMenu()
        Updater.shared.checkAutomatically()
        print("[SlideWand] startup complete")
        Log.line("startup complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // menu-bar app: closing windows doesn't quit
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The 1s menu timer must not fire while AppKit tears the app down: a
        // tick landing mid-teardown crashed on quit (EXC_BAD_ACCESS inside
        // updateMenu). Stop the camera too so it releases promptly.
        menuTimer?.invalidate()
        menuTimer = nil
        controller?.stop()
        Log.line("applicationWillTerminate: timer stopped, camera released")
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "hand.wave", accessibilityDescription: "SlideWand") {
                button.image = img
            } else {
                button.title = "🪄"
            }
        }
        let menu = NSMenu()
        statusLineItem = NSMenuItem(title: "Starting…", action: #selector(grantAccessibility),
                                    keyEquivalent: "")
        statusLineItem.target = self
        statusLineItem.toolTip = "Click for Accessibility help when blocked"
        menu.addItem(statusLineItem)
        menu.addItem(NSMenuItem(title: "Open Gesture Test…", action: #selector(openTest), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Calibrate Wand…", action: #selector(openCalibrate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPrefs), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""))
        let previewItem = NSMenuItem(title: "Hide Camera Preview", action: #selector(togglePreview), keyEquivalent: "p")
        previewToggleItems.append(previewItem)
        menu.addItem(previewItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SlideWand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// Full main menu bar (File, View, Window, Help…). The app is a regular
    /// Dock app, so it gets a real menu — the status-item menu alone isn't it.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        func wired(_ item: NSMenuItem) -> NSMenuItem {
            if item.action != nil { item.target = self }
            return item
        }

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(wired(NSMenuItem(title: "About SlideWand", action: #selector(openAbout), keyEquivalent: "")))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(wired(NSMenuItem(title: "Preferences…", action: #selector(openPrefs), keyEquivalent: ",")))
        appMenu.addItem(wired(NSMenuItem(title: "Calibrate Wand…", action: #selector(openCalibrate), keyEquivalent: "")))
        appMenu.addItem(wired(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")))
        appMenu.addItem(wired(NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccessibility), keyEquivalent: "")))
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit SlideWand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu — mirrors the tray menu's action items
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(wired(NSMenuItem(title: "Open Gesture Test…", action: #selector(openTest), keyEquivalent: "")))
        fileMenu.addItem(wired(NSMenuItem(title: "Calibrate Wand…", action: #selector(openCalibrate), keyEquivalent: "")))
        fileMenu.addItem(wired(NSMenuItem(title: "Preferences…", action: #selector(openPrefs), keyEquivalent: "")))
        fileMenu.addItem(wired(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")))
        fileMenu.addItem(NSMenuItem.separator())
        let filePreviewItem = wired(NSMenuItem(title: "Hide Camera Preview", action: #selector(togglePreview), keyEquivalent: ""))
        previewToggleItems.append(filePreviewItem)
        fileMenu.addItem(filePreviewItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(wired(NSMenuItem(title: "Close Window", action: #selector(closeFrontWindow), keyEquivalent: "w")))
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let viewPreviewItem = wired(NSMenuItem(title: "Hide Camera Preview", action: #selector(togglePreview), keyEquivalent: ""))
        previewToggleItems.append(viewPreviewItem)
        viewMenu.addItem(viewPreviewItem)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        let frontItem = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        frontItem.target = NSApp
        windowMenu.addItem(frontItem)
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(wired(NSMenuItem(title: "SlideWand on GitHub", action: #selector(openGitHub), keyEquivalent: "")))
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string:
                "Hand-gesture slide control for your Mac.\n\n" +
                "Wave the tip of your wand ← / → to change slides.\n\n" +
                "Native Swift · Vision + AVFoundation · everything on-device.\n" +
                "Ad-hoc signed (not Apple-notarized).\n\n" +
                "Tip: after updating, if keys stop working, toggle SlideWand " +
                "off and on in Settings → Privacy & Security → Accessibility."),
        ])
    }

    @objc private func grantAccessibility() {
        if KeySender.requestAccessibilityTrust() {
            controller.accessibilityOK = true
            controller.refreshHUD()
            return
        }
        // Still untrusted: the usual cause is macOS tying the grant to the
        // previous build's signature — the switch looks on but no longer
        // applies. Walk the user through the remove-and-re-add fix.
        let alert = NSAlert()
        alert.messageText = "SlideWand still isn't trusted"
        alert.informativeText =
            "macOS ties Accessibility permission to each build. After updating, " +
            "the old grant stops applying even though the switch still looks on.\n\n" +
            "Fix: in Settings → Privacy & Security → Accessibility, remove " +
            "SlideWand with the – button, then re-add it with the + button " +
            "(choose /Applications/SlideWand.app). It usually takes effect within " +
            "a couple of seconds; if the red banner doesn't clear, quit and " +
            "relaunch SlideWand."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            KeySender.openAccessibilitySettings()
        }
    }

    @objc private func closeFrontWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/AXIOVEX/slidewand") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func updateMenu() {
        tickCount += 1
        if tickCount % 15 == 0 {
            Log.line("heartbeat t=\(tickCount)s previewVisible=\(previewWindow?.isVisible ?? false) appWindows=\(NSApp.windows.count) active=\(NSApp.isActive)")
        }
        if let t = transientStatus {
            statusLineItem.title = t
            return
        }
        guard controller != nil else { return }
        let cam: String
        if controller.cameraRunning {
            cam = "Camera on"
        } else if controller.cameraError != nil {
            cam = "Camera off"
        } else {
            cam = "Camera starting…"
        }
        let ax = controller.accessibilityOK ? "keys sending" : "ACCESSIBILITY BLOCKED"
        statusLineItem.title = "\(cam) · \(ax)"
        if let button = statusItem.button {
            button.contentTintColor = (!controller.cameraRunning || !controller.accessibilityOK)
                ? .systemRed : nil
        }
    }

    @objc private func openTest() {
        testController.show()
    }

    @objc private func openCalibrate() {
        calibrateController.showWindow(nil)
    }

    @objc private func openPrefs() {
        prefsController.show()
    }

    @objc private func checkUpdates() {
        Updater.shared.check(interactive: true)
    }

    /// Transient one-line status (e.g. "Downloading update…") shown in place of
    /// the normal camera/key line until cleared with nil.
    func setTransientStatus(_ s: String?) {
        transientStatus = s
        updateMenu()
    }

    @objc private func togglePreview() {
        let vis = previewWindow.isVisible
        previewWindow.setIsVisible(!vis)
        let title = vis ? "Show Camera Preview" : "Hide Camera Preview"
        previewToggleItems.forEach { $0.title = title }
    }
}
