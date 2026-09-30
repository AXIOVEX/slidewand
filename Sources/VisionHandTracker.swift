import AVFoundation
import Vision
import CoreGraphics

// MARK: - Camera capture + Vision hand pose -> 21 normalized landmarks
//      + rectangle detection -> physical wand candidates

protocol HandTrackerDelegate: AnyObject {
    /// Called on the main thread. `points` is nil when no confident hand is visible.
    /// Points use GestureEngine convention: x grows to the user's right, y grows down.
    /// `wands` carries every stick-like rectangle seen in the same frame.
    func handTracker(_ tracker: VisionHandTracker, didUpdate points: [Pt]?, wands: [WandCandidate])
}

/// One stick-like rectangle: a candidate for the physical wand.
/// All geometry uses top-left origin, x to the user's right (matches the mirrored preview).
struct WandCandidate {
    /// Tip = midpoint of the short edge highest on screen.
    let tip: Pt
    /// Four corners [topLeft, topRight, bottomRight, bottomLeft] for drawing.
    let corners: [Pt]
    /// Long-axis length (normalized units).
    let length: Double
    /// Length / width shape ratio.
    let aspect: Double
    /// Mean color of a small patch around the tip, 0...1 RGB.
    let tipColor: (r: Double, g: Double, b: Double)
}

final class VisionHandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var delegate: HandTrackerDelegate?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.slidewand.video")
    private let request = VNDetectHumanHandPoseRequest()
    private let rectRequest: VNDetectRectanglesRequest = {
        let r = VNDetectRectanglesRequest()
        r.minimumAspectRatio = 0.05
        r.maximumAspectRatio = 20.0
        r.minimumSize = 0.02
        r.maximumObservations = 10
        return r
    }()

    /// Vision joint names in MediaPipe 21-point order (wrist, thumb 1-4, index 5-8, ...).
    private let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    var captureSession: AVCaptureSession { return session }

    /// Per-joint remembered positions: a joint that dips below the confidence
    /// threshold keeps its last good position instead of nuking the whole
    /// frame. Fist-like wand grips always have curled/occluded joints, so the
    /// old all-or-nothing gate meant those frames never arrived at all.
    private var remembered: [Pt?] = Array(repeating: nil, count: 21)
    /// Freshness of each joint in the most recently delivered frame.
    private(set) var jointFresh: [Bool] = Array(repeating: false, count: 21)

    func start() throws {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw NSError(domain: "SlideWand", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera found."])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "SlideWand", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot use the camera (in use by another app?)."])
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(domain: "SlideWand", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot configure camera output."])
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                           orientation: .up,
                                           options: [:])
        do {
            try handler.perform([request, rectRequest])
            let wands = buildWandCandidates(from: rectRequest.results as? [VNRectangleObservation] ?? [],
                                            pixelBuffer: pixelBuffer)
            guard let obs = request.results?.first as? VNHumanHandPoseObservation else {
                remembered = Array(repeating: nil, count: 21)
                notify(nil, wands: wands, fresh: Array(repeating: false, count: 21))
                return
            }
            let recognized = try obs.recognizedPoints(.all)
            var lm: [Pt?] = []
            lm.reserveCapacity(21)
            var fresh = [Bool](repeating: false, count: 21)
            for (i, joint) in joints.enumerated() {
                if let p = recognized[joint], p.confidence >= 0.2 {
                    // Vision: origin bottom-left, x grows to the subject's left on a
                    // front camera. Convert to engine convention: user's right = +x,
                    // top-left origin (matches the mirrored preview).
                    let pt = Pt(x: 1.0 - Double(p.location.x),
                                y: 1.0 - Double(p.location.y))
                    lm.append(pt)
                    remembered[i] = pt
                    fresh[i] = true
                } else {
                    lm.append(remembered[i])
                }
            }
            // Deliver the frame when the wrist anchor plus most of the hand is
            // known; never-seen joints fall back to the wrist position.
            let knownCount = lm.compactMap { $0 }.count
            guard let wrist = lm[0], knownCount >= 14 else {
                notify(nil, wands: wands, fresh: Array(repeating: false, count: 21))
                return
            }
            notify(lm.map { $0 ?? wrist }, wands: wands, fresh: fresh)
        } catch {
            notify(nil, wands: [], fresh: Array(repeating: false, count: 21))
        }
    }

    private func notify(_ points: [Pt]?, wands: [WandCandidate], fresh: [Bool]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.jointFresh = fresh
            self.delegate?.handTracker(self, didUpdate: points, wands: wands)
        }
    }

    // MARK: Physical wand candidates

    /// Vision coordinates (bottom-left origin) -> top-left origin, x mirrored
    /// to match the preview, same conversion as the hand landmarks.
    private func toView(_ v: CGPoint) -> Pt {
        Pt(x: 1.0 - Double(v.x), y: 1.0 - Double(v.y))
    }

    private func buildWandCandidates(from observations: [VNRectangleObservation],
                                     pixelBuffer: CVPixelBuffer) -> [WandCandidate] {
        var out: [WandCandidate] = []
        for obs in observations {
            guard obs.confidence >= 0.3 else { continue }
            // Work in Vision coords for the color sample, convert after.
            let vcs = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
            let edges = [(vcs[0], vcs[1]), (vcs[1], vcs[2]), (vcs[2], vcs[3]), (vcs[3], vcs[0])]
            let lens = edges.map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }
            guard let length = lens.max(), let width = lens.min(),
                  length >= 0.12, length / max(width, 1e-6) >= 3.5 else { continue }
            // The two ends are the two shortest edges; the tip is the one
            // highest on screen (smallest y in top-left-origin coords).
            let order = lens.indices.sorted { lens[$0] < lens[$1] }
            let mids = edges.map { CGPoint(x: ($0.0.x + $0.1.x) / 2, y: ($0.0.y + $0.1.y) / 2) }
            let tipV = [mids[order[0]], mids[order[1]]].max(by: { $0.y < $1.y })!
            let color = sampleTipColor(at: tipV, in: pixelBuffer)
            let corners = vcs.map(toView)
            let tip = toView(tipV)
            out.append(WandCandidate(tip: tip, corners: corners, length: Double(length),
                                     aspect: Double(length / max(width, 1e-6)),
                                     tipColor: color))
        }
        return out
    }

    /// Mean color of a 5x5 patch around a Vision-coords point. The pixel buffer
    /// is raw (unmirrored): px = x*W, py = (1-y)*H.
    private func sampleTipColor(at v: CGPoint, in pixelBuffer: CVPixelBuffer) -> (Double, Double, Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (0, 0, 0) }
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        let row = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let cx = Int(v.x * CGFloat(w)), cy = Int((1 - v.y) * CGFloat(h))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                let x = min(max(cx + dx, 0), w - 1), y = min(max(cy + dy, 0), h - 1)
                let p = base.advanced(by: y * row + x * 4).assumingMemoryBound(to: UInt8.self)
                b += Double(p[0]); g += Double(p[1]); r += Double(p[2]); n += 1
            }
        }
        return (r / (255 * n), g / (255 * n), b / (255 * n))
    }
}
