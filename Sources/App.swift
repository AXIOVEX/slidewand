import AppKit
import AVFoundation
import CoreGraphics
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
            preview.applyMirroring()
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
        if let pts = points, handOK {
            let c = palmCentroid(pts)
            cx = c.x; cy = c.y
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

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLineItem: NSMenuItem!
    private var previewItem: NSMenuItem!
    private var previewWindow: NSWindow!
    private var controller: WandController!
    private var testController: TestWindowController!
    private var prefsController: PreferencesWindowController!
    private var transientStatus: String? = nil
    private var menuTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()

        controller = WandController()
        testController = TestWindowController(wand: controller)
        prefsController = PreferencesWindowController()

        previewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                                styleMask: [.titled, .closable, .miniaturizable],
                                backing: .buffered,
                                defer: false)
        previewWindow.title = "SlideWand — camera preview"
        previewWindow.center()
        previewWindow.contentView = controller.view
        previewWindow.makeKeyAndOrderFront(nil)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // menu-bar app: closing windows doesn't quit
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
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPrefs), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""))
        previewItem = NSMenuItem(title: "Hide Camera Preview", action: #selector(togglePreview), keyEquivalent: "p")
        menu.addItem(previewItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SlideWand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func updateMenu() {
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
        previewItem.title = vis ? "Show Camera Preview" : "Hide Camera Preview"
    }
}
