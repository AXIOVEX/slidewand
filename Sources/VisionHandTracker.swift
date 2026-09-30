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
                notify(nil)
                return
            }
            let recognized = try obs.recognizedPoints(.all)
            var lm: [Pt] = []
            lm.reserveCapacity(21)
            var confident = 0
            for joint in joints {
                guard let p = recognized[joint], p.confidence >= 0.2 else {
                    notify(nil)
                    return
                }
                // Vision: origin bottom-left, x grows to the subject's left on a
                // front camera. Convert to engine convention: user's right = +x,
                // top-left origin (matches the mirrored preview).
                lm.append(Pt(x: 1.0 - Double(p.location.x),
                             y: 1.0 - Double(p.location.y)))
                if p.confidence >= 0.3 { confident += 1 }
            }
            notify(confident >= 15 ? lm : nil)
        } catch {
            notify(nil)
        }
    }

    private func notify(_ points: [Pt]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.handTracker(self, didUpdate: points)
        }
    }
}
