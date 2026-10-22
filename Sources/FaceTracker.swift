import CoreImage
import Vision

/// One tracked face, in normalized image coordinates (0...1, origin bottom-left),
/// carrying the same measurements Photo Booth's PBFace keeps.
struct Face {
    var center: CGPoint
    var leftEye: CGPoint
    var rightEye: CGPoint
    var mouth: CGPoint
    /// Half the face width as a fraction of the image width.
    var radius: Double
    /// Tilt of the line from the left eye to the right eye, in radians.
    var angle: Double
    var trackingID: Int

    /// PBFace's eyeAmount: radius × 1.2.
    var eyeAmount: Double { radius * 1.2 }

    func pixel(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

/// Finds faces with Vision on a background queue and smooths them over time.
/// Photo Booth uses a private Vision request (VNTrackLegacyFaceCoreObjectRequest);
/// this uses the public landmarks request instead.
final class FaceTracker {
    private let queue = DispatchQueue(label: "MyPhotoBooth.faces")
    private let lock = NSLock()
    private var busy = false
    private var tracked: [TrackedFace] = []
    private var nextID = 1

    private struct TrackedFace {
        var face: Face
        var lastSeen: Double
    }

    /// The current smoothed faces.
    var faces: [Face] {
        lock.lock()
        defer { lock.unlock() }
        return tracked.map(\.face)
    }

    /// Offers a frame for detection. Frames that arrive while a detection is running are skipped.
    func submit(_ frame: CIImage) {
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()

        queue.async {
            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(ciImage: frame, options: [:])
            try? handler.perform([request])
            let observations = request.results ?? []
            self.update(with: observations.compactMap(FaceTracker.face(from:)),
                        time: CFAbsoluteTimeGetCurrent())
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
        }
    }

    static func face(from observation: VNFaceObservation) -> Face? {
        let box = observation.boundingBox
        guard let landmarks = observation.landmarks,
              let left = landmarks.leftEye, let right = landmarks.rightEye,
              let lips = landmarks.outerLips ?? landmarks.innerLips else { return nil }

        func centroid(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let points = region.normalizedPoints
            guard !points.isEmpty else { return CGPoint(x: box.midX, y: box.midY) }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let n = CGFloat(points.count)
            return CGPoint(x: box.minX + sum.x / n * box.width, y: box.minY + sum.y / n * box.height)
        }

        // Order the eyes by where they sit in the picture, not by anatomy, so the maths below
        // (and the cheek, temple and halo offsets) works the same on the mirrored frame.
        let eyes = [centroid(left), centroid(right)].sorted { $0.x < $1.x }
        let leftEye = eyes[0], rightEye = eyes[1]
        // Same definitions as PBFace: angle = atan2 of the eye line, radius = half the box width.
        let angle = rightEye.x == leftEye.x ? 0 : atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x)
        return Face(center: CGPoint(x: box.midX, y: box.midY), leftEye: leftEye, rightEye: rightEye,
                    mouth: centroid(lips), radius: box.width * 0.5, angle: angle, trackingID: 0)
    }

    private func update(with detected: [Face], time: Double) {
        lock.lock()
        defer { lock.unlock() }
        var unmatched = tracked
        var result: [TrackedFace] = []
        for var face in detected {
            // Match each new face to the nearest face from the last pass.
            let nearest = unmatched.indices.min { a, b in
                distance(unmatched[a].face.center, face.center) < distance(unmatched[b].face.center, face.center)
            }
            if let index = nearest, distance(unmatched[index].face.center, face.center) < 0.25 {
                let previous = unmatched.remove(at: index)
                face = smooth(previous.face, toward: face, dt: time - previous.lastSeen)
                face.trackingID = previous.face.trackingID
            } else {
                face.trackingID = nextID
                nextID += 1
            }
            result.append(TrackedFace(face: face, lastSeen: time))
        }
        // Keep a lost face briefly so a missed detection doesn't make effects blink.
        result += unmatched.filter { time - $0.lastSeen < 0.4 }
        tracked = result
    }

    /// Eases measurements toward the new detection over roughly 50 ms, the duration
    /// Photo Booth's PBFace gives its PBEffectSmoothener instances.
    private func smooth(_ old: Face, toward new: Face, dt: Double) -> Face {
        let k = min(1, max(0.15, dt / 0.05))
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        var face = new
        face.center = mix(old.center, new.center)
        face.leftEye = mix(old.leftEye, new.leftEye)
        face.rightEye = mix(old.rightEye, new.rightEye)
        face.mouth = mix(old.mouth, new.mouth)
        face.radius = old.radius + (new.radius - old.radius) * k
        face.angle = old.angle + (new.angle - old.angle) * k
        return face
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
