import AVFoundation
import Vision
import CoreGraphics

// MARK: - Camera capture + Vision hand pose -> 21 normalized landmarks

protocol HandTrackerDelegate: AnyObject {
    /// Called on the main thread. `points` is nil when no confident hand is visible.
    /// Points use GestureEngine convention: x grows to the user's right, y grows down.
    func handTracker(_ tracker: VisionHandTracker, didUpdate points: [Pt]?)
}

final class VisionHandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var delegate: HandTrackerDelegate?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.slidewand.video")
    private let request = VNDetectHumanHandPoseRequest()

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
            try handler.perform([request])
            guard let obs = request.results?.first as? VNHumanHandPoseObservation else {
                remembered = Array(repeating: nil, count: 21)
                notify(nil, fresh: Array(repeating: false, count: 21))
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
                notify(nil, fresh: Array(repeating: false, count: 21))
                return
            }
            notify(lm.map { $0 ?? wrist }, fresh: fresh)
        } catch {
            notify(nil, fresh: Array(repeating: false, count: 21))
        }
    }

    private func notify(_ points: [Pt]?, fresh: [Bool]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.jointFresh = fresh
            self.delegate?.handTracker(self, didUpdate: points)
        }
    }
}
