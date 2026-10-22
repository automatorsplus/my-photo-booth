import AppKit
import CoreImage

/// Hearts for Lovestruck and birds for Dizzy, drawn in code rather than copied from
/// Photo Booth's PNGs. Each sprite's origin is at its centre.
enum Sprites {
    static let heart: CIImage = draw(size: CGSize(width: 144, height: 136)) { ctx, size in
        let w = size.width, h = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w / 2, y: h * 0.06))
        path.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.66),
                      control1: CGPoint(x: w * 0.30, y: h * 0.30), control2: CGPoint(x: w * 0.02, y: h * 0.42))
        path.addArc(center: CGPoint(x: w * 0.27, y: h * 0.70), radius: w * 0.25,
                    startAngle: .pi * 1.05, endAngle: .pi * 0.05, clockwise: true)
        path.addArc(center: CGPoint(x: w * 0.73, y: h * 0.70), radius: w * 0.25,
                    startAngle: .pi * 0.95, endAngle: -.pi * 0.05, clockwise: true)
        path.addCurve(to: CGPoint(x: w / 2, y: h * 0.06),
                      control1: CGPoint(x: w * 0.98, y: h * 0.42), control2: CGPoint(x: w * 0.70, y: h * 0.30))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.93, green: 0.10, blue: 0.25, alpha: 1))
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.0, blue: 0.10, alpha: 1))
        ctx.setLineWidth(5)
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.fillEllipse(in: CGRect(x: w * 0.18, y: h * 0.62, width: w * 0.16, height: h * 0.14))
    }

    /// Four wing positions, like Photo Booth's bird0...bird3 frames.
    static let birdFrames: [CIImage] = (0..<4).map { frame in
        draw(size: CGSize(width: 150, height: 108)) { ctx, size in
            let w = size.width, h = size.height
            let wingLift = [0.9, 0.35, -0.35, 0.35][frame]
            // Tail
            ctx.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: w * 0.22, y: h * 0.45))
            tail.addLine(to: CGPoint(x: w * 0.02, y: h * 0.62))
            tail.addLine(to: CGPoint(x: w * 0.06, y: h * 0.36))
            tail.closeSubpath()
            ctx.addPath(tail)
            ctx.fillPath()
            // Body and head
            ctx.setFillColor(CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.56, height: h * 0.48))
            ctx.fillEllipse(in: CGRect(x: w * 0.56, y: h * 0.42, width: w * 0.30, height: h * 0.40))
            ctx.setFillColor(CGColor(red: 0.95, green: 0.90, blue: 0.75, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: w * 0.30, y: h * 0.24, width: w * 0.32, height: h * 0.22))
            // Beak and eye
            ctx.setFillColor(CGColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1))
            let beak = CGMutablePath()
            beak.move(to: CGPoint(x: w * 0.84, y: h * 0.66))
            beak.addLine(to: CGPoint(x: w * 0.99, y: h * 0.58))
            beak.addLine(to: CGPoint(x: w * 0.84, y: h * 0.53))
            beak.closeSubpath()
            ctx.addPath(beak)
            ctx.fillPath()
            ctx.setFillColor(.white)
            ctx.fillEllipse(in: CGRect(x: w * 0.69, y: h * 0.60, width: w * 0.10, height: h * 0.14))
            ctx.setFillColor(.black)
            ctx.fillEllipse(in: CGRect(x: w * 0.72, y: h * 0.63, width: w * 0.05, height: h * 0.07))
            // Wing, rotated for the flap frame
            ctx.saveGState()
            ctx.translateBy(x: w * 0.42, y: h * 0.50)
            ctx.rotate(by: CGFloat(wingLift))
            ctx.setFillColor(CGColor(red: 0.10, green: 0.35, blue: 0.75, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -w * 0.04, y: -h * 0.10, width: w * 0.36, height: h * 0.20))
            ctx.restoreGState()
        }
    }

    private static func draw(size: CGSize, _ body: (CGContext, CGSize) -> Void) -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return CIImage.empty() }
        body(ctx, size)
        guard let image = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2))
    }
}
