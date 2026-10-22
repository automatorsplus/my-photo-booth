import AVFoundation
import CoreImage

/// Delivers mirrored webcam frames as CIImages with their extent at the origin.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let frameQueue = DispatchQueue(label: "MyPhotoBooth.camera")
    private let lock = NSLock()
    private var latestFrame: CIImage?

    /// Called on the camera queue for every frame.
    var onFrame: ((CIImage) -> Void)?

    var latest: CIImage? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    /// Asks for camera access if needed and starts capture. The completion runs on the
    /// main queue with an error message, or nil once frames are on their way.
    func start(completion: @escaping (String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure(completion) } else { completion(Camera.deniedMessage) }
                }
            }
        default:
            completion(Camera.deniedMessage)
        }
    }

    func stop() {
        frameQueue.async { self.session.stopRunning() }
    }

    private static let deniedMessage =
        "Camera access is off. Turn on MyPhotoBooth in System Settings → Privacy & Security → Camera, then reopen the app."

    private func configure(_ completion: @escaping (String?) -> Void) {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            completion("No camera was found.")
            return
        }
        session.beginConfiguration()
        // Photo Booth sizes its effects against a 720-line frame (imageScale = height / 720).
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        frameQueue.async { self.session.startRunning() }
        completion(nil)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let raw = CIImage(cvPixelBuffer: pixelBuffer)
        // Show the user a mirror image, as Photo Booth does (its composition flips with scaleX -1).
        let flip = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -raw.extent.width, y: 0)
        let frame = raw.transformed(by: flip)
        lock.lock()
        latestFrame = frame
        lock.unlock()
        onFrame?(frame)
    }
}
