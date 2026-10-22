import AppKit
import CoreImage
import MetalKit

/// Draws a CIImage supplied by `composer` into a Metal drawable, about 30 times a second.
final class BoothView: MTKView, MTKViewDelegate {
    /// Returns the image to show for a drawable of the given pixel size.
    var composer: ((CGSize) -> CIImage?)?
    /// Click or drag position in drawable pixels, origin bottom-left (the same space as the composed image).
    var onPointer: ((CGPoint, _ isDrag: Bool) -> Void)?
    /// Return true if the key was handled.
    var onKey: ((NSEvent) -> Bool)?

    let ciContext: CIContext
    private let commandQueue: MTLCommandQueue

    init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal is not available on this Mac.")
        }
        commandQueue = queue
        ciContext = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false, .name: "MyPhotoBooth"])
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        preferredFramesPerSecond = 30
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let size = drawableSize
        guard size.width > 0, size.height > 0,
              let image = composer?(size),
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }
        let destination = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                              pixelFormat: colorPixelFormat, commandBuffer: buffer) { drawable.texture }
        destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        _ = try? ciContext.startTask(toRender: image, to: destination)
        buffer.present(drawable)
        buffer.commit()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onPointer?(pixelPoint(event), false) }
    override func mouseDragged(with event: NSEvent) { onPointer?(pixelPoint(event), true) }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let scale = bounds.width > 0 ? drawableSize.width / bounds.width : 1
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }
}

/// Photo Booth-style red shutter button with a camera glyph.
final class ShutterButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height) - 4
        let circle = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        let pressed = isHighlighted
        let top = isEnabled ? NSColor(red: 0.95, green: 0.25, blue: 0.22, alpha: 1) : NSColor.systemGray
        let bottom = isEnabled ? NSColor(red: 0.70, green: 0.08, blue: 0.08, alpha: 1) : NSColor.darkGray
        NSGradient(starting: pressed ? bottom : top, ending: pressed ? top : bottom)?
            .draw(in: NSBezierPath(ovalIn: circle), angle: -90)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
        if let glyph = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: side * 0.36, weight: .semibold)) {
            let tinted = NSImage(size: glyph.size, flipped: false) { rect in
                glyph.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let s = tinted.size
            tinted.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
        }
    }
}
