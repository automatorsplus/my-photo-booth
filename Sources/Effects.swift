import CoreImage

/// Everything an effect needs to render one frame.
struct EffectInput {
    var image: CIImage
    var time: Double
    var faces: [Face] = []
    /// Normalized point the user clicked, used as the centre of the slider distortions.
    var point = CGPoint(x: 0.5, y: 0.5)
    /// 0...1, like Photo Booth's effect slider.
    var slider = 0.5
    /// True for the small live tiles in the effect grid.
    var preview = false

    var extent: CGRect { image.extent }
    var width: Double { extent.width }
    var height: Double { extent.height }
    var diagonal: Double { hypot(width, height) }
    /// PBEffect imageScale: sizes are tuned for a 720-line frame.
    var imageScale: Double { height / 720 }
    /// PBEffectDistortion sliderRadius: the slider value as a fraction of the image diagonal.
    var sliderRadius: Double { diagonal * slider }
    /// PBEffect imageXY: the clicked point in pixels.
    var touch: CIVector { CIVector(x: point.x * width, y: point.y * height) }
    /// PBEffect imageCenter.
    var middle: CIVector { CIVector(x: width / 2, y: height / 2) }
}

enum EffectKind { case normal, color, distortion, face }

struct Effect {
    let name: String
    let kind: EffectKind
    let wantsSlider: Bool
    private let render: (EffectInput) -> CIImage

    init(_ name: String, _ kind: EffectKind, slider: Bool = false, render: @escaping (EffectInput) -> CIImage) {
        self.name = name
        self.kind = kind
        self.wantsSlider = slider
        self.render = render
    }

    func apply(_ input: EffectInput) -> CIImage {
        render(input).cropped(to: input.extent)
    }
}

/// The 24 effects Photo Booth 13.1 ships, in the order of its EffectsOrdering.plist,
/// with the filter chains and constants read from the binary. See PHOTO_BOOTH_FINDINGS.md.
enum EffectCatalog {
    static let normal = Effect("Normal", .normal) { $0.image }

    static let pages: [[Effect]] = [faceEffects, colorEffects, distortionEffects]

    /// Nine tiles for a page: its eight effects with Normal in the middle.
    static func grid(page: Int) -> [Effect] {
        var tiles = pages[page]
        tiles.insert(normal, at: 4)
        return tiles
    }

    // MARK: Colour effects (PBEffectColor subclasses)

    static let colorEffects: [Effect] = [
        Effect("Sepia", .color) { input in
            input.image.warmed
                .colorControls(saturation: 0, brightness: 0.15, contrast: 1.3)
                .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.8])
        },
        Effect("Black & White", .color) { input in
            input.image.warmed
                .colorControls(saturation: 0, brightness: 0.15, contrast: 1.3)
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.7, kCIInputRadiusKey: 1.5])
        },
        Effect("Plastic Camera", .color, render: plasticCamera),
        Effect("Comic Book", .color, render: comicBook),
        Effect("Color Pencil", .color, render: colorPencil),
        Effect("Glow", .color) { input in
            let d = input.diagonal
            return input.image
                .colorControls(saturation: 1, brightness: 0.6491, contrast: 2.407)
                .clampedToExtent()   // keeps the blurs from darkening the frame edges
                .applyingFilter("CIGloom", parameters: [kCIInputRadiusKey: 0.03 * d * 0.5, kCIInputIntensityKey: 1])
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 0.0485 * d * 0.5, kCIInputIntensityKey: 0.5794])
                .cropped(to: input.extent)
                .colorControls(saturation: 1, brightness: 0.1, contrast: 1.25)
        },
        Effect("Thermal Camera", .color) { input in
            input.image.warmed
                .colorControls(saturation: 0, brightness: 0.7863, contrast: 2.676)
                .applyingFilter("CIColorMap", parameters: ["inputGradientImage": Gradients.thermal])
                .colorControls(saturation: 1, brightness: 0.25, contrast: 1.5)
        },
        Effect("X-Ray", .color) { input in
            let inverted = input.image.applyingFilter("CIColorInvert")
            let halo = inverted.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5.0])
                .cropped(to: input.extent)
            return halo.withAlpha(0.5)
                .composited(over: inverted)
                .colorControls(saturation: 0, brightness: -1, contrast: 2.45)
                .applyingFilter("CIColorMap", parameters: ["inputGradientImage": Gradients.xray])
        },
    ]

    /// Two coloured light leaks multiplied together, then brightened.
    private static func plasticCamera(_ input: EffectInput) -> CIImage {
        let w = input.width, h = input.height, rect = input.extent
        func leak(concentration: Double, pointsAt: CIVector, position: CIVector, matrix: [CIVector]) -> CIImage {
            let light = solid(gray(0.5), rect).applyingFilter("CISpotLight", parameters: [
                "inputBrightness": 10, kCIInputColorKey: CIColor.white, "inputConcentration": concentration,
                "inputLightPointsAt": pointsAt, "inputLightPosition": position,
            ]).cropped(to: rect)
            return input.image
                .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: solid(.black, rect), kCIInputMaskImageKey: light])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": matrix[0], "inputGVector": matrix[1], "inputBVector": matrix[2],
                    "inputAVector": matrix[3], "inputBiasVector": matrix[4]])
        }
        let orange = leak(concentration: 0.1533,
                          pointsAt: CIVector(x: 0.4 * w, y: 2 * h, z: 0),
                          position: CIVector(x: 0.4 * w, y: -0.15 * w, z: 0.4 * w),
                          matrix: [CIVector(x: 2, y: 0, z: 0, w: 0.1), CIVector(x: 0, y: 2, z: 0, w: 0),
                                   CIVector(x: 0, y: 0, z: 1, w: 0), CIVector(x: 0, y: 0, z: 0, w: 1),
                                   CIVector(x: 0.02, y: 0.02, z: 0, w: 0)])
        let cyan = leak(concentration: 0.3234,
                        pointsAt: CIVector(x: 0.75 * w, y: 0.5 * h, z: 0),
                        position: CIVector(x: 0.75 * w, y: 0.75 * w, z: 0.5 * h),
                        matrix: [CIVector(x: 1.5, y: 0, z: 0, w: 0), CIVector(x: 0, y: 2, z: 0, w: 0),
                                 CIVector(x: 0, y: 0, z: 0, w: 0), CIVector(x: 0, y: 0, z: 0, w: 1),
                                 CIVector(x: 0.1, y: 0.5, z: 0.5, w: 0.25)])
        return orange
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: cyan])
            .colorControls(saturation: 1.1, brightness: 0.25, contrast: 1.5)
    }

    /// Posterized colour, white halftone dots, and inked outlines.
    private static func comicBook(_ input: EffectInput) -> CIImage {
        let rect = input.extent
        let posterized = input.image
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                kCIInputRadiusKey: 19, "inputShadowAmount": 1.5, "inputHighlightAmount": 1.0])
            .colorControls(saturation: 1.7, brightness: 0.2, contrast: 1.5)
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 12])
        let halftone = input.image
            .applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor.white, kCIInputIntensityKey: 1])
            .applyingFilter("CISpotColor", parameters: [
                "inputCenterColor1": gray(0.3), "inputReplacementColor1": CIColor.black,
                "inputCloseness1": 0.4368, "inputContrast1": 0,
                "inputCenterColor2": gray(0.7), "inputReplacementColor2": gray(0.8),
                "inputCloseness2": 0.4147, "inputContrast2": 0.7932,
                "inputCenterColor3": CIColor.white, "inputReplacementColor3": CIColor.white,
                "inputCloseness3": 0, "inputContrast3": 0])
            .applyingFilter("CIDotScreen", parameters: [
                kCIInputCenterKey: CIVector(x: 0, y: 0), kCIInputAngleKey: -0.40107666210829696,
                kCIInputWidthKey: (input.preview ? 10 : 15) * input.imageScale, kCIInputSharpnessKey: 0.7])
        let outline = input.image
            .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 6.283, kCIInputIntensityKey: 1.0])
            .colorControls(saturation: 0, brightness: 0.8792, contrast: 2.54)
            .applyingFilter("CISpotColor", parameters: [
                "inputCenterColor1": CIColor.black, "inputReplacementColor1": CIColor.black,
                "inputCloseness1": 0.5, "inputContrast1": 1,
                "inputCenterColor2": gray(0.7), "inputReplacementColor2": gray(0.99),
                "inputCloseness2": 0.45, "inputContrast2": 1,
                "inputCenterColor3": gray(0.9), "inputReplacementColor3": CIColor.white,
                "inputCloseness3": 0, "inputContrast3": 1])
        let dotted = solid(.white, rect).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: posterized, kCIInputMaskImageKey: halftone])
        let inked = outline.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: posterized])
        return dotted.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: inked])
    }

    /// A dodged colour sketch multiplied by diagonal pencil strokes made from blurred noise.
    private static func colorPencil(_ input: EffectInput) -> CIImage {
        let rect = input.extent
        let toned = input.image.colorControls(saturation: 1, brightness: 0.3471, contrast: 1.609)
        let paper = input.image.applyingFilter("CISpotColor", parameters: [
            "inputCenterColor1": CIColor.black, "inputReplacementColor1": CIColor.black,
            "inputCloseness1": 0.5, "inputContrast1": 1,
            "inputCenterColor2": gray(0.7), "inputReplacementColor2": CIColor.white,
            "inputCloseness2": 0.5, "inputContrast2": 0.2656,
            "inputCenterColor3": CIColor.white, "inputReplacementColor3": CIColor.white,
            "inputCloseness3": 0, "inputContrast3": 0])
        let sketch = toned.applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: paper])
        // Photo Booth tiles its static.png noise; this generates comparable noise instead.
        let margin = 40 * input.imageScale
        let strokes = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: rect.insetBy(dx: -margin, dy: -margin))
            .settingAlphaOne(in: rect.insetBy(dx: -margin, dy: -margin))
            .applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: 17 * input.imageScale, kCIInputAngleKey: 0.5759586531581288])
            .cropped(to: rect)
            .colorControls(saturation: 0, brightness: 0.5, contrast: 2)
        return sketch
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: strokes])
            .colorControls(saturation: 0.7, brightness: 0.2995, contrast: 2.131)
    }

    // MARK: Distortions (PBEffectDistortion subclasses)

    static let distortionEffects: [Effect] = [
        Effect("Bulge", .distortion, slider: true) { input in
            mirrored(input).applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: input.touch, kCIInputRadiusKey: input.sliderRadius * 0.75, kCIInputScaleKey: 0.5])
        },
        Effect("Dent", .distortion, slider: true) { input in
            mirrored(input).applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: input.touch, kCIInputRadiusKey: input.sliderRadius * 0.425, kCIInputScaleKey: -1])
        },
        Effect("Twirl", .distortion, slider: true) { input in
            mirrored(input).applyingFilter("CITwirlDistortion", parameters: [
                kCIInputCenterKey: input.touch, kCIInputRadiusKey: input.sliderRadius * 0.35,
                kCIInputAngleKey: input.slider * .pi])   // slider × 180°
        },
        Effect("Squeeze", .distortion, slider: true) { input in
            mirrored(input).applyingFilter("CIPinchDistortion", parameters: [
                kCIInputCenterKey: input.touch, kCIInputRadiusKey: input.sliderRadius * 0.215,
                kCIInputScaleKey: input.slider * 1.413])
        },
        Effect("Mirror", .distortion) { input in
            mirrored(input).applyingFilter("CIKaleidoscope", parameters: [
                kCIInputCenterKey: input.middle, "inputCount": 1, kCIInputAngleKey: Double.pi / 2])
        },
        Effect("Light Tunnel", .distortion, slider: true) { input in
            mirrored(input).applyingFilter("CICircleSplashDistortion", parameters: [
                kCIInputCenterKey: input.touch, kCIInputRadiusKey: input.sliderRadius * 0.336])
        },
        Effect("Fish Eye", .distortion) { input in
            // Fish Eye ignores the slider: its sliderValue is fixed at 0.5.
            let factor = input.diagonal * 0.5 * 1.69
            let extent = input.extent
            return Kernels.fishEye.apply(extent: .infinite, roiCallback: { _, _ in extent }, image: mirrored(input),
                                         arguments: [input.middle, factor]) ?? input.image
        },
        Effect("Stretch", .distortion) { input in
            let h = input.height
            let amp = 0.1 * h
            return Kernels.funHouse.apply(extent: .infinite, roiCallback: { _, r in r.insetBy(dx: -amp, dy: -amp) },
                                          image: mirrored(input), arguments: [input.middle, h, amp, 0.15 * h]) ?? input.image
        },
    ]

    /// PBEffect.outputImage for distortions: the frame reflected across its edges.
    private static func mirrored(_ input: EffectInput) -> CIImage {
        Kernels.mirrorEdges(input.image)
    }

    // MARK: Face effects (PBEffectFace subclasses)

    static let faceEffects: [Effect] = [
        faceEffect("Space Alien") { image, face, input in
            let size = input.extent.size
            var out = bump(image, at: face.pixel(face.leftEye, in: size), radiusScale: face.radius, scale: 0.5, input)
            out = bump(out, at: face.pixel(face.rightEye, in: size), radiusScale: face.radius, scale: 0.5, input)
            return bump(out, at: face.pixel(face.mouth, in: size), radiusScale: 0.3, scale: -0.6, input)
        },
        Effect("Nose Twirl", .face, render: noseTwirl),
        faceEffect("Chipmunk") { image, face, input in
            // Bulges sit below the eyes, toward the mouth: the cheeks.
            let drop = eyeToMouth(face) / 1.5
            let side = face.radius * 0.125
            let s = sin(face.angle), c = cos(face.angle)
            let left = CGPoint(x: face.leftEye.x - side * c - drop * s, y: face.leftEye.y - drop * c + side * s)
            let right = CGPoint(x: face.rightEye.x + side * c - drop * s, y: face.rightEye.y - drop * c + side * s)
            let size = input.extent.size
            let out = bump(image, at: face.pixel(left, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
            return bump(out, at: face.pixel(right, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
        },
        Effect("Lovestruck", .face, render: lovestruck),
        Effect("Dizzy", .face, render: dizzy),
        faceEffect("Blockhead") { image, face, input in
            // Bulges sit above the eyes, at the temples, widening the top of the head.
            let lift = eyeToMouth(face) / 1.5 * 0.5
            let s = sin(face.angle), c = cos(face.angle)
            let left = CGPoint(x: face.leftEye.x + lift * s, y: face.leftEye.y + lift * c)
            let right = CGPoint(x: face.rightEye.x + lift * s, y: face.rightEye.y + lift * c)
            let size = input.extent.size
            let out = bump(image, at: face.pixel(left, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
            return bump(out, at: face.pixel(right, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
        },
        faceEffect("Bug Out") { image, face, input in
            let size = input.extent.size
            let out = bump(image, at: face.pixel(face.leftEye, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
            return bump(out, at: face.pixel(face.rightEye, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
        },
        faceEffect("Frog") { image, face, input in
            let size = input.extent.size
            var out = bump(image, at: face.pixel(face.leftEye, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
            out = bump(out, at: face.pixel(face.rightEye, in: size), radiusScale: face.eyeAmount, scale: 0.5, input)
            let mouth = face.pixel(face.mouth, in: size)
            return bump(out, at: CGPoint(x: mouth.x, y: mouth.y * 0.7), radiusScale: 0.2186, scale: 0.5, input)
        },
    ]

    /// PBEffectFace.outputImage: start from the edge-mirrored frame and apply the effect once per face.
    private static func faceEffect(_ name: String,
                                   _ perFace: @escaping (CIImage, Face, EffectInput) -> CIImage) -> Effect {
        Effect(name, .face) { input in
            input.faces.reduce(mirrored(input)) { image, face in perFace(image, face, input) }
        }
    }

    /// PBEffectFace applyBump:forCenter:radiusScale:scale: — radius is 0.75 × radiusScale × diagonal.
    private static func bump(_ image: CIImage, at center: CGPoint, radiusScale: Double, scale: Double,
                             _ input: EffectInput) -> CIImage {
        image.applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: center),
            kCIInputRadiusKey: input.diagonal * radiusScale * 0.75,
            kCIInputScaleKey: scale])
    }

    private static func eyeToMouth(_ face: Face) -> Double {
        let mid = CGPoint(x: (face.leftEye.x + face.rightEye.x) / 2, y: (face.leftEye.y + face.rightEye.y) / 2)
        return hypot(mid.x - face.mouth.x, mid.y - face.mouth.y)
    }

    /// A twirl on the nose whose direction depends on which half of the frame the face is in,
    /// easing over half a second when it flips, like PBNoseTwirl's 500 ms smoother.
    private static func noseTwirl(_ input: EffectInput) -> CIImage {
        input.faces.reduce(mirrored(input)) { image, face in
            let center = face.pixel(face.center, in: input.extent.size)
            let radius = input.diagonal * 0.35 * face.radius + 0.1 * center.y
            let degrees = face.radius * 180 + 25
            let target = (center.x < input.width / 2 ? 1 : -1) * degrees * .pi / 180
            let angle = TwirlSmoother.shared.value(target, faceID: face.trackingID, time: input.time,
                                                   live: !input.preview)
            return image.applyingFilter("CITwirlDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: center), kCIInputRadiusKey: radius, kCIInputAngleKey: angle])
        }
    }

    // MARK: Sprite effects

    /// Hearts circling the head, each pulsing and wobbling, smaller and fainter behind it.
    private static func lovestruck(_ input: EffectInput) -> CIImage {
        var out = input.image
        for face in input.faces {
            let center = face.pixel(face.center, in: input.extent.size)
            let faceSize = face.radius * input.width
            let count = 8
            // Back half of the orbit first, so near hearts draw on top.
            let hearts = (0..<count).map { i -> (Double, Double) in
                let phase = Double(i) / Double(count) * 2 * .pi
                let angle = phase + input.time * 0.9
                return (angle, sin(angle))
            }.sorted { $0.1 > $1.1 }
            for (i, (angle, depth)) in hearts.enumerated() {
                let near = (1 - depth) / 2   // 0 at the back of the orbit, 1 at the front
                let pulse = 1 + 0.12 * sin(input.time * 2 * .pi / 0.5 + Double(i))
                let scale = faceSize * (0.35 + 0.25 * near) * pulse / Double(Sprites.heart.extent.width)
                let wobble = 15 * sin(input.time * 2 * .pi / 3 + Double(i) * 1.3) * .pi / 180
                let x = center.x + cos(angle) * faceSize * 1.3
                let y = center.y + faceSize * 0.6 + depth * faceSize * 0.25
                let heart = Sprites.heart
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(rotationAngle: wobble))
                    .transformed(by: CGAffineTransform(translationX: x, y: y))
                out = heart.withAlpha(0.55 + 0.45 * near).composited(over: out)
            }
        }
        return out
    }

    /// Cartoon birds flapping round an ellipse above the head.
    private static func dizzy(_ input: EffectInput) -> CIImage {
        var out = input.image
        for face in input.faces {
            let faceSize = face.radius * input.width
            let head = face.pixel(face.center, in: input.extent.size)
            // _elipsisCenterForFace: 1.85 × radius above the face centre, along the face's up axis.
            let lift = faceSize * 1.85 * input.height / input.width
            let center = CGPoint(x: head.x - sin(face.angle) * lift, y: head.y + cos(face.angle) * lift)
            let a = faceSize * 1.4, b = faceSize * 0.3
            let count = 5
            let birds = (0..<count).map { i -> (Double, Double) in
                let angle = Double(i) / Double(count) * 2 * .pi + input.time * 2 * .pi / 3.5
                return (angle, sin(angle))
            }.sorted { $0.1 > $1.1 }
            for (i, (angle, depth)) in birds.enumerated() {
                let near = (1 - depth) / 2
                let frame = Sprites.birdFrames[Int(input.time * 12 + Double(i)) % 4]
                let scale = faceSize * (0.003 + 0.002 * near)
                let facingLeft = cos(angle + .pi / 2) < 0
                let p = CGPoint(x: center.x + cos(angle) * a, y: center.y - depth * b)
                out = frame
                    .transformed(by: CGAffineTransform(scaleX: facingLeft ? -scale : scale, y: scale))
                    .transformed(by: CGAffineTransform(rotationAngle: face.angle))
                    .transformed(by: CGAffineTransform(translationX: p.x, y: p.y))
                    .composited(over: out)
            }
        }
        return out
    }
}

// MARK: Helpers

private func solid(_ color: CIColor, _ rect: CGRect) -> CIImage {
    CIImage(color: color).cropped(to: rect)
}

private func gray(_ value: Double) -> CIColor {
    CIColor(red: value, green: value, blue: value)
}

extension CIImage {
    /// The CITemperatureAndTint stage that starts Sepia, Black & White and Thermal Camera.
    var warmed: CIImage {
        applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 500), "inputTargetNeutral": CIVector(x: 1000, y: 300)])
    }

    func colorControls(saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation, kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast])
    }

    /// PBEffectUtil fadeImage:alpha: — a colour matrix that scales alpha.
    func withAlpha(_ alpha: Double) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
    }
}

/// Colour ramps for CIColorMap, with stops sampled from Photo Booth's thermalMap.png and xrayMap.png.
enum Gradients {
    static let thermal = ramp(["1b0026", "3700ee", "00a6ff", "00ffe0", "00ff6e", "14ff00",
                               "88ff00", "f6ff00", "ffa700", "ff2400", "ff0000"])
    static let xray = ramp(["000000", "011917", "0a3533", "25504e", "446e6c", "638e8b",
                            "83aeab", "a2cdca", "bde8e5", "d3fdfb", "ffffff"])

    private static func ramp(_ hexes: [String]) -> CIImage {
        let width = 256
        let colors = hexes.map { hex -> (Double, Double, Double) in
            let v = Int(hex, radix: 16) ?? 0
            return (Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255)
        }
        var bytes = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            let t = Double(x) / Double(width - 1) * Double(colors.count - 1)
            let i = min(Int(t), colors.count - 2), f = t - Double(i)
            let a = colors[i], b = colors[i + 1]
            bytes[x * 4] = UInt8((a.0 + (b.0 - a.0) * f) * 255)
            bytes[x * 4 + 1] = UInt8((a.1 + (b.1 - a.1) * f) * 255)
            bytes[x * 4 + 2] = UInt8((a.2 + (b.2 - a.2) * f) * 255)
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4, size: CGSize(width: width, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}

/// Eases Nose Twirl's angle toward its target over 500 ms per face.
final class TwirlSmoother {
    static let shared = TwirlSmoother()
    private var state: [Int: (value: Double, time: Double)] = [:]
    private let lock = NSLock()

    func value(_ target: Double, faceID: Int, time: Double, live: Bool) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard live else { return state[faceID]?.value ?? target }
        guard let previous = state[faceID] else {
            state[faceID] = (target, time)
            return target
        }
        let k = min(1, max(0, (time - previous.time) / 0.5))
        let value = previous.value + (target - previous.value) * k
        state[faceID] = (value, time)
        return value
    }
}
