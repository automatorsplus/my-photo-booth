import CoreImage
import Foundation
import Vision

/// `--render in.jpg outDir`: applies every effect to a still image and writes PNGs,
/// plus the three effect-grid pages, so the effects can be checked without a camera.
enum RenderTool {
    static func run(input: String, outputDirectory: String) -> Int32 {
        guard let loaded = CIImage(contentsOf: URL(fileURLWithPath: input), options: [.applyOrientationProperty: true]) else {
            print("Couldn't read \(input)")
            return 1
        }
        // Match the camera: 720 lines, extent at the origin.
        let s = 720 / loaded.extent.height
        var image = loaded.transformed(by: CGAffineTransform(scaleX: s, y: s))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        image = image.cropped(to: CGRect(x: 0, y: 0, width: image.extent.width.rounded(.down), height: 720))

        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        var faces = (request.results ?? []).compactMap(FaceTracker.face(from:))
        for (i, _) in faces.enumerated() { faces[i].trackingID = i + 1 }
        if faces.isEmpty {
            print("No face found, so the face effects use a stand-in face in the middle of the picture.")
            faces = [Face(center: CGPoint(x: 0.5, y: 0.5), leftEye: CGPoint(x: 0.44, y: 0.56),
                          rightEye: CGPoint(x: 0.56, y: 0.56), mouth: CGPoint(x: 0.5, y: 0.38),
                          radius: 0.13, angle: 0, trackingID: 1)]
        } else {
            print("Found \(faces.count) face(s).")
        }

        let out = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let context = CIContext()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func write(_ picture: CIImage, _ name: String) {
            let url = out.appendingPathComponent(name)
            do {
                try context.writePNGRepresentation(of: picture, to: url, format: .RGBA8, colorSpace: space)
                print(url.path)
            } catch {
                print("Failed \(name): \(error.localizedDescription)")
            }
        }

        let all = [EffectCatalog.normal] + EffectCatalog.pages.flatMap { $0 }
        for (index, effect) in all.enumerated() {
            let picture = effect.apply(EffectInput(image: image, time: 1.0, faces: faces))
            let slug = effect.name.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and")
            write(picture, String(format: "%02d-%@.png", index, slug))
        }
        for page in EffectCatalog.pages.indices {
            let canvas = CGRect(x: 0, y: 0, width: 1500, height: 900)
            let (grid, _) = EffectGrid.compose(frame: image, faces: faces, time: 1.0, tiles: EffectCatalog.grid(page: page), selected: "Normal",
                                               point: CGPoint(x: 0.5, y: 0.5), slider: 0.5, canvas: canvas, pointScale: 1.5)
            let background = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.07)).cropped(to: canvas)
            write(grid.composited(over: background), "grid-page\(page + 1).png")
        }
        return 0
    }
}
