import AppKit
import AVFoundation
import CoreGraphics

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

        // Camera notice (denied / error)
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
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func applyMirroring() {
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.isVideoMirrored = true
        }
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }
}

// MARK: - Controller: engine loop

final class WandController: NSObject, HandTrackerDelegate {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 560))

    private let tracker = VisionHandTracker()
    private let preview: PreviewView
    private let overlay = OverlayView()

    private let swipe = SwipeDetector()
    private let hold = HoldDetector()
    private let gate = TriggerGate()
    private var trail: [Pt] = []

    private var fpsEma = 30.0
    private var prevT = ProcessInfo.processInfo.systemUptime
    private var lastAction: String? = nil
    private var lastActionT: Double = 0
    private var notice: String? = nil

    private var axOK = true
    private var axPrompted = false
    private var lastAxCheck: Double = 0

    private let minHandHeight = 0.16

    override init() {
        preview = PreviewView(session: tracker.captureSession)
        super.init()
        preview.frame = NSRect(x: 10, y: 70, width: 640, height: 480)
        preview.autoresizingMask = [.width, .height]
        overlay.frame = NSRect(x: 0, y: 0, width: 660, height: 560)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(preview)
        view.addSubview(overlay)
        axOK = KeySender.accessibilityTrusted()
    }

    func start() {
        tracker.delegate = self
        do {
            try tracker.start()
            preview.applyMirroring()
        } catch {
            notice = (error as NSError).localizedDescription
            render(points: nil)
        }
    }

    func showCameraDenied() {
        notice = "Camera access denied — enable it in System Settings → Privacy & Security → Camera."
        render(points: nil)
    }

    // MARK: HandTrackerDelegate (main thread)

    func handTracker(_ tracker: VisionHandTracker, didUpdate points: [Pt]?) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - prevT
        prevT = now
        if dt > 0 { fpsEma = 0.9 * fpsEma + 0.1 * (1.0 / dt) }

        // Accessibility is re-checked periodically; macOS never prompts, so we
        // open the Settings page once and show a banner until granted.
        if now - lastAxCheck > 2.0 {
            lastAxCheck = now
            axOK = KeySender.accessibilityTrusted()
            if !axOK && !axPrompted {
                axPrompted = true
                KeySender.openAccessibilitySettings()
            }
        }

        var gesture: Gesture = .unknown
        var cx = 0.0, cy = 0.0
        let handOK = points.map { handHeight($0) >= minHandHeight } ?? false
        if let pts = points, handOK {
            let c = palmCentroid(pts)
            cx = c.x; cy = c.y
            gesture = classifyHand(pts)
            trail.append(Pt(x: cx, y: cy))
            if trail.count > 24 { trail.removeFirst() }
        }

        var action: String? = nil
        let dir: SwipeDir? = handOK
            ? swipe.update(t: now, present: true, x: cx, y: cy)
            : swipe.update(t: now, present: false)
        if let dir = dir, gate.ready(now) {
            action = (dir == .right) ? "NEXT" : "PREV"
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
        hud.accessibilityOK = axOK
        hud.notice = notice
        overlay.render(hud)
    }
}

// MARK: - App bootstrap

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: WandController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "SlideWand — wave to change slides"
        window.center()

        controller = WandController()
        window.contentView = controller.view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            controller.start()
        case .notDetermined:
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit SlideWand",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q"))
        NSApp.mainMenu = menu
    }
}
