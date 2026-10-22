import CoreImage

/// Core Image kernels for the three effects that Photo Booth builds from its own kernels
/// rather than built-in filters. Written in the Core Image Kernel Language because this
/// machine has no Metal shader compiler; the API is deprecated but still works.
enum Kernels {
    /// Reflects the image across its edges indefinitely, so a distortion that pulls pixels
    /// from outside the frame sees a mirror image rather than transparency.
    static let mirrorTile: CIWarpKernel = {
        guard let kernel = CIWarpKernel(source: """
            kernel vec2 mirrorTile(vec2 size)
            {
                vec2 t = destCoord() / size;
                t = 1.0 - abs(2.0 * fract(0.5 * t) - 1.0);
                return t * size;
            }
            """) else { fatalError("mirrorTile kernel failed to compile") }
        return kernel
    }()

    // Fish Eye and Stretch are warp kernels: they return where to sample from. Apply them with
    // an infinite extent and crop afterwards; a kernel's own bounded extent wasn't honoured once
    // the result was moved into a grid tile, and it smeared across the whole canvas.

    /// Fish Eye: each pixel samples from 0.6·d / (1 − d²/f²) along its ray from the centre.
    static let fishEye: CIWarpKernel = {
        guard let kernel = CIWarpKernel(source: """
            kernel vec2 lens(vec2 c, float f)
            {
                vec2 off = destCoord() - c;
                float r = length(off);
                return c + off * (0.6 / (1.0 - (r * r) / (f * f)));
            }
            """) else { fatalError("fishEye kernel failed to compile") }
        return kernel
    }()

    /// Stretch: a sine displacement that fades out with distance from the centre.
    static let funHouse: CIWarpKernel = {
        guard let kernel = CIWarpKernel(source: """
            kernel vec2 funHouse(vec2 c, float reach, float amp, float period)
            {
                vec2 p = destCoord();
                vec2 w = smoothstep(0.0, 1.0, 1.0 - clamp(abs(p - c) / reach, 0.0, 1.0));
                return p - amp * sin((p - c.y) / period) * w;
            }
            """) else { fatalError("funHouse kernel failed to compile") }
        return kernel
    }()

    static func mirrorEdges(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return mirrorTile.apply(extent: .infinite, roiCallback: { _, _ in extent }, image: image,
                                arguments: [CIVector(x: extent.width, y: extent.height)]) ?? image
    }
}
