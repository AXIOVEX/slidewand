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
    var tipIndex: Int? = nil
    var calibrating: Bool = false
    var calibrationProgress: Double = 0
    var calibrationHint: String = ""
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
            // Wand tip marker (from calibration)
            if let ti = hud.tipIndex, ti < pts.count {
                let p = pts[ti]
                NSColor.cyan.setFill()
                NSBezierPath(ovalIn: NSRect(x: X(p.x) - 7, y: Y(p.y) - 7, width: 14, height: 14)).fill()
                text("TIP", at: CGPoint(x: X(p.x) + 12, y: Y(p.y) - 16), size: 11,
                     color: .cyan, bold: true)
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

        // Calibration guidance overlay: where to put the wand + what to do
        if hud.calibrating {
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: NSRect(x: vx, y: vy, width: vw, height: vh)).fill()

            // Target box: hold the wand in here
            let bw: CGFloat = 280, bh: CGFloat = 340
            let bx = vx + (vw - bw) / 2, by = vy + (vh - bh) / 2 - 10
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let box = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh),
                                   xRadius: 14, yRadius: 14)
            box.lineWidth = 2.5
            box.setLineDash([10, 7], count: 2, phase: 0)
            box.stroke()

            // Up arrow: tip points up
            let ax = bx + bw / 2
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let arrow = NSBezierPath()
            arrow.move(to: CGPoint(x: ax, y: by + 60))
            arrow.line(to: CGPoint(x: ax, y: by + 150))
            arrow.move(to: CGPoint(x: ax - 16, y: by + 128))
            arrow.line(to: CGPoint(x: ax, y: by + 152))
            arrow.line(to: CGPoint(x: ax + 16, y: by + 128))
            arrow.lineWidth = 4
            arrow.lineCapStyle = .round
            arrow.stroke()
            text("TIP UP", at: CGPoint(x: ax - 32, y: by + 30), size: 15,
                 color: .white, bold: true)

            // Live tip dot: what the app currently thinks the tip is
            if let pts = hud.points, hud.handOK,
               let top = pts.enumerated().min(by: { $0.element.y < $1.element.y }) {
                NSColor.yellow.setFill()
                NSBezierPath(ovalIn: NSRect(x: X(top.element.x) - 8, y: Y(top.element.y) - 8,
                                            width: 16, height: 16)).fill()
            }

            // Instruction + progress
            text(hud.calibrationHint, at: CGPoint(x: bx + 18, y: by + bh + 12), size: 14,
                 color: .white, bold: true)
            text("Don't wave yet — just hold still.", at: CGPoint(x: bx + 18, y: by - 24),
                 size: 12, color: .lightGray)
            let pbw = bw - 36
            NSColor.darkGray.setFill()
            NSBezierPath(roundedRect: NSRect(x: bx + 18, y: by - 48, width: pbw, height: 12),
                         xRadius: 6, yRadius: 6).fill()
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: NSRect(x: bx + 18, y: by - 48,
                                             width: pbw * CGFloat(hud.calibrationProgress), height: 12),
                         xRadius: 6, yRadius: 6).fill()
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

    // Wand-tip calibration: learn which landmark is the tip of the wand.
    var calibration: WandCalibration? = WandCalibration.load()
    var calibrating = false
    var calibrationMessage: String? = nil
    private var calFrames: [[Pt]] = []
    private var calFresh: [[Bool]] = []
    private var calTipTrail: [Pt] = []
    private var calDeadline: Double = 0
    private let calDuration = 2.5
    /// Calibration is more forgiving about hand size than gesture detection —
    /// frames are averaged and steadiness-checked anyway.
    private let calMinHandSize = 0.10
    private var lastCalSawHand = false

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

    // MARK: Wand calibration

    var calibrationProgress: Double {
        guard calibrating else { return 0 }
        let remain = max(0, calDeadline - ProcessInfo.processInfo.systemUptime)
        return min(1.0, 1.0 - remain / calDuration)
    }

    /// Begin a calibration capture: hold the wand up, tip pointing up, steady.
    func startCalibration() {
        calFrames.removeAll()
        calFresh.removeAll()
        calTipTrail.removeAll()
        calibrationMessage = nil
        lastCalSawHand = false
        calibrating = true
        calDeadline = ProcessInfo.processInfo.systemUptime + calDuration
        gestureLabel = "calibrating — hold your wand still…"
        swipe.reset(); hold.reset(); trail.removeAll()
    }

    /// Live hint for the calibration window + preview overlay.
    var calibrationHint: String {
        guard calibrating else { return "" }
        return lastCalSawHand ? "I see your wand — hold it still…"
                              : "Show your wand to the camera…"
    }

    func cancelCalibration() {
        calibrating = false
        gestureLabel = "wave quickly ← / →"
    }

    func clearCalibration() {
        WandCalibration.clear()
        calibration = nil
        calibrationMessage = nil
    }

    private func captureCalibrationFrame(now: Double, points: [Pt]?, handOK: Bool, fresh: [Bool]) {
        lastCalSawHand = points != nil && handOK
        if let pts = points, handOK {
            calFrames.append(pts)
            calFresh.append(fresh)
            if let top = pts.enumerated().min(by: { $0.element.y < $1.element.y }) {
                calTipTrail.append(top.element)
            }
        }
        if now >= calDeadline { finishCalibration() }
    }

    private func finishCalibration() {
        calibrating = false
        defer { render(points: nil) }
        let need = Int(calDuration * 15) // require a solid majority of frames
        guard calFrames.count >= need, !calTipTrail.isEmpty else {
            calibrationMessage = "I couldn't see your wand — hold it up in view and try again."
            gestureLabel = "wave quickly ← / →"
            return
        }
        // Average each landmark over the capture window; the tip is the topmost.
        var avg = [Pt](repeating: Pt(x: 0, y: 0), count: 21)
        let n = Double(calFrames.count)
        for f in calFrames {
            for i in 0..<21 { avg[i].x += f[i].x / n; avg[i].y += f[i].y / n }
        }
        guard let tipEntry = avg.enumerated().min(by: { $0.element.y < $1.element.y }) else {
            calibrationMessage = "Calibration failed — please try again."
            gestureLabel = "wave quickly ← / →"
            return
        }
        // Steadiness check: the tip must not have wandered during capture.
        let xs = calTipTrail.map { $0.x }
        let ys = calTipTrail.map { $0.y }
        let xRange = (xs.max() ?? 0.0) - (xs.min() ?? 0.0)
        let yRange = (ys.max() ?? 0.0) - (ys.min() ?? 0.0)
        let wander = xRange + yRange
        guard wander < 0.18 else {
            calibrationMessage = "Too shaky — hold your wand still and try again."
            gestureLabel = "wave quickly ← / →"
            return
        }
        // The tip must have been genuinely seen (not a remembered position)
        // in at least half the frames.
        let tipFreshCount = calFresh.filter { $0[tipEntry.offset] }.count
        guard Double(tipFreshCount) >= 0.5 * Double(calFrames.count) else {
            calibrationMessage = "I couldn't get a clear look at the tip — point it toward the camera and try again."
            gestureLabel = "wave quickly ← / →"
            return
        }
        let tip = tipEntry.element
        let cal = WandCalibration(tipIndex: tipEntry.offset, restX: tip.x, restY: tip.y,
                                  scale: handHeight(avg), calibratedAt: Date())
        cal.save()
        calibration = cal
        calibrationMessage = "Tracking your \(WandCalibration.landmarkName(cal.tipIndex)). " +
            "Wave the tip ← / → to change slides."
        gestureLabel = "wave quickly ← / →"
    }

    func refreshHUD() {
        render(points: nil)
    }

    // MARK: HandTrackerDelegate (main thread)

    func handTracker(_ tracker: VisionHandTracker, didUpdate points: [Pt]?) {
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
        if calibrating {
            // Learning the wand tip — gesture detection is paused meanwhile.
            // Calibration is more forgiving about hand size; frames are
            // averaged and steadiness-checked anyway.
            let calOK = points.map { handHeight($0) >= calMinHandSize } ?? false
            captureCalibrationFrame(now: now, points: points, handOK: calOK,
                                    fresh: tracker.jointFresh)
            render(points: points, handOK: calOK)
            return
        }
        if let pts = points, handOK {
            // Track the calibrated wand tip when we know it; otherwise the palm.
            let track: Pt
            if let cal = calibration, cal.tipIndex < pts.count {
                track = pts[cal.tipIndex]
            } else {
                track = palmCentroid(pts)
            }
            cx = track.x; cy = track.y
            gesture = classifyHand(pts)
            trail.append(Pt(x: cx, y: cy))
            if trail.count > 24 { trail.removeFirst() }
        }
        switch gesture {
        case .openPalm: gestureLabel = "OPEN PALM — hold for NEXT"
        case .fist: gestureLabel = "FIST — hold for PREV"
        case .unknown: gestureLabel = handOK ? "wave quickly ← / →" : "show your hand to the camera"
        }

        var action: String? = nil
        var source = ""
        let dir: SwipeDir? = handOK
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
        if action == nil, handOK {
            let (fired, p) = hold.update(t: now, present: true, gesture: gesture,
                                        x: cx, y: cy, armed: gate.ready(now))
            progress = p
            if let fired = fired, gate.ready(now) {
                action = fired
                source = fired == "NEXT" ? "hold palm" : "hold fist"
                gate.fire(now)
                swipe.reset()
            }
        } else if !handOK {
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
        hud.tipIndex = calibration?.tipIndex
        hud.calibrating = calibrating
        hud.calibrationProgress = calibrationProgress
        hud.calibrationHint = calibrationHint
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
        if let cal = wand.calibration {
            statusParts.append("Wand: \(WandCalibration.landmarkName(cal.tipIndex)) ✓")
        } else {
            statusParts.append("Wand: not calibrated")
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

// MARK: - Wand calibration window: teach SlideWand which fingertip is the tip

final class CalibrationWindowController: NSWindowController {
    private weak var wand: WandController?
    private var timer: Timer?

    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let startButton = NSButton(title: "Start Calibration", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    init(wand: WandController) {
        self.wand = wand
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Calibrate Wand"
        win.center()
        super.init(window: win)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 300))
        win.contentView = view

        let title = NSTextField(labelWithString: "Teach SlideWand your wand")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 20, y: 248, width: 400, height: 22)
        view.addSubview(title)

        let help = NSTextField(wrappingLabelWithString:
            "Hold your hand up like a wand, tip pointing up, and keep it still. " +
            "SlideWand watches for a couple of seconds, learns which fingertip is the tip, " +
            "and tracks that point from now on — waves go off the tip and how it moves. " +
            "Watch the camera preview while you do it.")
        help.frame = NSRect(x: 20, y: 158, width: 400, height: 84)
        view.addSubview(help)

        progress.frame = NSRect(x: 20, y: 128, width: 400, height: 16)
        progress.minValue = 0; progress.maxValue = 1
        progress.isIndeterminate = false
        progress.doubleValue = 0
        view.addSubview(progress)

        statusLabel.frame = NSRect(x: 20, y: 96, width: 400, height: 24)
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
            progress.doubleValue = wand.calibrationProgress
            statusLabel.stringValue = wand.calibrationHint
            statusLabel.textColor = .labelColor
            startButton.isEnabled = false
        } else {
            progress.doubleValue = wand.calibration != nil ? 1.0 : 0
            startButton.isEnabled = true
            if let msg = wand.calibrationMessage {
                statusLabel.stringValue = msg
                statusLabel.textColor = wand.calibration != nil ? .systemGreen : .systemOrange
                // Keep the message until the next calibration run.
            } else if let cal = wand.calibration {
                let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
                statusLabel.stringValue =
                    "Calibrated \(fmt.string(from: cal.calibratedAt)) — tracking your " +
                    "\(WandCalibration.landmarkName(cal.tipIndex))."
                statusLabel.textColor = .systemGreen
            } else {
                statusLabel.stringValue = "Not calibrated — waves track the palm for now."
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
        Log.line("didFinishLaunching: start (v0.1.2)")
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
        statusLineItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
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
            "(choose /Applications/SlideWand.app). It takes effect within a " +
            "couple of seconds — no relaunch needed."
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
