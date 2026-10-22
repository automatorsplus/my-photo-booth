import AppKit
import CoreImage

/// The 3×3 page of live effect previews, Normal in the middle, each tile labelled.
enum EffectGrid {
    /// Composes one page and returns it with each tile's rectangle, for hit-testing.
    static func compose(frame: CIImage, faces: [Face], time: Double, tiles: [Effect], selected: String,
                        point: CGPoint, slider: Double, canvas: CGRect, pointScale: CGFloat) -> (CIImage, [CGRect]) {
        let gap = 8 * pointScale
        let cellWidth = (canvas.width - gap * 4) / 3
        let cellHeight = (canvas.height - gap * 4) / 3
        let aspect = frame.extent.width / frame.extent.height
        let tileWidth = min(cellWidth, cellHeight * aspect)
        let tileHeight = tileWidth / aspect
        // Each tile renders its effect on a downscaled frame, so nine effects stay cheap.
        let s = tileWidth / frame.extent.width
        let small = frame.transformed(by: CGAffineTransform(scaleX: s, y: s))

        var image = CIImage.empty()
        var rects: [CGRect] = []
        for (index, effect) in tiles.enumerated() {
            let row = CGFloat(index / 3), column = CGFloat(index % 3)
            let cellX = canvas.minX + gap + column * (cellWidth + gap)
            let cellY = canvas.maxY - gap - (row + 1) * cellHeight - row * gap
            let rect = CGRect(x: (cellX + (cellWidth - tileWidth) / 2).rounded(),
                              y: (cellY + (cellHeight - tileHeight) / 2).rounded(),
                              width: tileWidth.rounded(), height: tileHeight.rounded())
            rects.append(rect)

            let input = EffectInput(image: small, time: time, faces: faces, point: point, slider: slider, preview: true)
            var tile = effect.apply(input)
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
                .cropped(to: rect)
            let band = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 22 * pointScale)
            tile = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45)).cropped(to: band).composited(over: tile)
            let text = Labels.image(effect.name, size: 13 * pointScale)
            tile = text.transformed(by: CGAffineTransform(
                translationX: (rect.midX - text.extent.width / 2).rounded(),
                y: (band.midY - text.extent.height / 2).rounded())).composited(over: tile)
            if effect.name == selected {
                let frameRect = rect.insetBy(dx: -3 * pointScale, dy: -3 * pointScale)
                tile = tile.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9)).cropped(to: frameRect))
            }
            image = tile.composited(over: image)
        }
        return (image, rects)
    }
}

/// White label text rendered once per name and size.
enum Labels {
    private static var cache: [String: CIImage] = [:]
    private static let lock = NSLock()

    static func image(_ text: String, size: CGFloat) -> CIImage {
        let key = "\(text)@\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
        ])
        let filter = CIFilter(name: "CIAttributedTextImageGenerator")
        filter?.setValue(string, forKey: "inputText")
        filter?.setValue(1, forKey: "inputScaleFactor")
        let image = filter?.outputImage ?? CIImage.empty()
        let placed = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        cache[key] = placed
        return placed
    }
}
