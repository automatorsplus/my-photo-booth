import AppKit
import CoreImage

/// The booth window: live preview, the effect grid, and the countdown → flash → save sequence.
final class BoothController: NSViewController {
    private let camera = Camera()
    private let tracker = FaceTracker()
    private let booth = BoothView()
    private var chime: CountdownChime?

    private let effectsButton = NSButton(title: "Effects", target: nil, action: nil)
    private let previousButton = NSButton(title: "◀", target: nil, action: nil)
    private let nextButton = NSButton(title: "▶", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let effectLabel = NSTextField(labelWithString: "Normal")
    private let slider = NSSlider(value: 0.5, minValue: 0.05, maxValue: 1, target: nil, action: nil)
    private let shutter = ShutterButton()
    private let countdownLabel = NSTextField(labelWithString: "")
    private let toastLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    // Main-thread state.
    private var effect = EffectCatalog.normal
    private var page = 0
    private var showingGrid = false
    private var point = CGPoint(x: 0.5, y: 0.5)
    private var sliderValue = 0.5
    private var frozen: CIImage?
    private var counting = false
    private var timers: [Timer] = []
    private var imageRect = CGRect.zero
    private var tileRects: [CGRect] = []

    static let unmirrorKey = "AutoFlipPhoto"

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 680))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        view = root

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor

        for button in [effectsButton, previousButton, nextButton] {
            button.bezelStyle = .rounded
            button.target = self
        }
        effectsButton.action = #selector(toggleGrid)
        previousButton.action = #selector(previousPage)
        nextButton.action = #selector(nextPage)
        shutter.target = self
        shutter.action = #selector(takePhoto)
        shutter.isBordered = false
        shutter.title = ""
        shutter.toolTip = "Take Photo (Space)"
        slider.target = self
        slider.action = #selector(sliderMoved)
        pageLabel.textColor = .secondaryLabelColor
        effectLabel.textColor = .labelColor
        effectLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let left = NSStackView(views: [effectsButton, previousButton, pageLabel, nextButton])
        left.spacing = 8
        let right = NSStackView(views: [effectLabel, slider])
        right.spacing = 12

        countdownLabel.font = .systemFont(ofSize: 180, weight: .heavy)
        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 12
        countdownLabel.shadow = shadow
        countdownLabel.isHidden = true

        toastLabel.font = .systemFont(ofSize: 13, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.drawsBackground = true
        toastLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        toastLabel.isHidden = true

        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.isHidden = true

        for v in [booth, bar, left, right, shutter, countdownLabel, toastLabel, messageLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        root.addSubview(booth)
        root.addSubview(bar)
        bar.addSubview(left)
        bar.addSubview(right)
        bar.addSubview(shutter)
        root.addSubview(countdownLabel)
        root.addSubview(toastLabel)
        root.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            booth.topAnchor.constraint(equalTo: root.topAnchor),
            booth.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            booth.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            booth.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 76),
            left.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            left.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            slider.widthAnchor.constraint(equalToConstant: 160),
            shutter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            shutter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 58),
            shutter.heightAnchor.constraint(equalToConstant: 58),
            countdownLabel.centerXAnchor.constraint(equalTo: booth.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: booth.centerYAnchor),
            toastLabel.centerXAnchor.constraint(equalTo: booth.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: booth.topAnchor, constant: 14),
            messageLabel.centerXAnchor.constraint(equalTo: booth.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: booth.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])

        booth.composer = { [weak self] size in self?.compose(size) }
        booth.onPointer = { [weak self] point, isDrag in self?.pointer(point, isDrag: isDrag) }
        booth.onKey = { [weak self] event in self?.key(event) ?? false }
        updateControls()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(booth)
        camera.onFrame = { [tracker] frame in tracker.submit(frame) }
        camera.start { [weak self] error in
            guard let self else { return }
            if let error {
                self.messageLabel.stringValue = error
                self.messageLabel.isHidden = false
            }
        }
        // Load the instrument now so the first countdown beep isn't late.
        DispatchQueue.main.async { self.chime = CountdownChime() }
    }

    func shutdown() {
        camera.stop()
    }

    // MARK: Drawing

    private func compose(_ size: CGSize) -> CIImage? {
        let canvas = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.07)).cropped(to: canvas)
        if let frozen {
            return fit(frozen, into: canvas).composited(over: background)
        }
        guard let frame = camera.latest else { return background }
        let time = CACurrentMediaTime()
        let faces = tracker.faces
        if showingGrid {
            let scale = booth.bounds.width > 0 ? size.width / booth.bounds.width : 1
            let (grid, rects) = EffectGrid.compose(frame: frame, faces: faces, time: time, tiles: EffectCatalog.grid(page: page),
                                                   selected: effect.name, point: point, slider: sliderValue,
                                                   canvas: canvas, pointScale: scale)
            tileRects = rects
            return grid.composited(over: background)
        }
        let input = EffectInput(image: frame, time: time, faces: faces, point: point, slider: sliderValue)
        return fit(effect.apply(input), into: canvas).composited(over: background)
    }

    /// Scales an image to fit the canvas, centred, and remembers where it landed for clicks.
    private func fit(_ image: CIImage, into canvas: CGRect) -> CIImage {
        let extent = image.extent
        let s = min(canvas.width / extent.width, canvas.height / extent.height)
        let w = extent.width * s, h = extent.height * s
        imageRect = CGRect(x: canvas.midX - w / 2, y: canvas.midY - h / 2, width: w, height: h)
        return image
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: imageRect.minX - extent.minX * s,
                                               y: imageRect.minY - extent.minY * s))
    }

    // MARK: Input

    private func pointer(_ location: CGPoint, isDrag: Bool) {
        guard !counting, frozen == nil else { return }
        if showingGrid {
            guard !isDrag, let index = tileRects.firstIndex(where: { $0.contains(location) }) else { return }
            select(EffectCatalog.grid(page: page)[index])
            setGrid(false)
        } else if effect.wantsSlider, imageRect.width > 0 {
            // Photo Booth's slider distortions centre on the clicked point (PBEffect setInputXY:).
            point = CGPoint(x: min(max((location.x - imageRect.minX) / imageRect.width, 0), 1),
                            y: min(max((location.y - imageRect.minY) / imageRect.height, 0), 1))
        }
    }

    private func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49, 36, 76: takePhoto(); return true                  // space, return, enter
        case 53:                                                    // escape
            if counting { cancelCountdown() } else if showingGrid { setGrid(false) }
            return true
        case 123: showingGrid ? previousPage() : stepEffect(-1); return true
        case 124: showingGrid ? nextPage() : stepEffect(1); return true
        default: return false
        }
    }

    // MARK: Effects

    @objc func toggleGrid() {
        guard !counting else { return }
        setGrid(!showingGrid)
    }

    private func setGrid(_ show: Bool) {
        showingGrid = show
        updateControls()
    }

    @objc func previousPage() {
        page = (page + EffectCatalog.pages.count - 1) % EffectCatalog.pages.count
        updateControls()
    }

    @objc func nextPage() {
        page = (page + 1) % EffectCatalog.pages.count
        updateControls()
    }

    private func stepEffect(_ delta: Int) {
        let all = [EffectCatalog.normal] + EffectCatalog.pages.flatMap { $0 }
        let index = all.firstIndex { $0.name == effect.name } ?? 0
        select(all[(index + delta + all.count) % all.count])
    }

    private func select(_ newEffect: Effect) {
        effect = newEffect
        point = CGPoint(x: 0.5, y: 0.5)
        if let found = EffectCatalog.pages.firstIndex(where: { $0.contains { $0.name == newEffect.name } }) {
            page = found
        }
        updateControls()
    }

    @objc private func sliderMoved() {
        sliderValue = slider.doubleValue
    }

    private func updateControls() {
        effectsButton.title = showingGrid ? "Done" : "Effects"
        effectsButton.isEnabled = !counting
        shutter.isEnabled = !counting && frozen == nil
        previousButton.isHidden = !showingGrid
        nextButton.isHidden = !showingGrid
        pageLabel.isHidden = !showingGrid
        pageLabel.stringValue = "Page \(page + 1) of \(EffectCatalog.pages.count)"
        effectLabel.stringValue = effect.name
        slider.isHidden = showingGrid || !effect.wantsSlider
        shutter.needsDisplay = true
    }

    // MARK: Taking a photo

    @objc func takePhoto() {
        guard !counting, frozen == nil, camera.latest != nil else { return }
        counting = true
        if showingGrid { showingGrid = false }
        updateControls()
        // PBCountdownController: 0.5 s after the click, three steps 0.8 s apart, each with a beep;
        // the photo is taken when the third step ends.
        let lead = 0.5, step = 0.8
        for (i, number) in ["3", "2", "1"].enumerated() {
            schedule(after: lead + Double(i) * step) { [weak self] in self?.showCount(number) }
        }
        schedule(after: lead + 3 * step) { [weak self] in self?.capture() }
    }

    private func schedule(after delay: Double, _ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func showCount(_ number: String) {
        countdownLabel.stringValue = number
        countdownLabel.isHidden = false
        chime?.beep()
    }

    private func cancelCountdown() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        countdownLabel.isHidden = true
        counting = false
        updateControls()
    }

    private func capture() {
        timers.removeAll()
        countdownLabel.isHidden = true
        guard let frame = camera.latest else {
            counting = false
            updateControls()
            return
        }
        // Same order as PBPhotoController record: freeze the picture, take it, then flash and click.
        let input = EffectInput(image: frame, time: CACurrentMediaTime(), faces: tracker.faces,
                                point: point, slider: sliderValue)
        let shown = effect.apply(input)
        frozen = shown
        var photo = shown
        if UserDefaults.standard.bool(forKey: Self.unmirrorKey) {
            photo = photo.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -frame.extent.width, y: 0))
        }
        Flash.fire()
        Flash.playShutterSound()

        let context = booth.ciContext
        let extent = frame.extent
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<URL, Error>
            if let image = context.createCGImage(photo, from: extent, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) {
                result = Result { try PhotoSaver.save(image) }
            } else {
                result = .failure(CocoaError(.fileWriteUnknown))
            }
            DispatchQueue.main.async { self.finishCapture(result) }
        }
    }

    private func finishCapture(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): showToast("Saved to Pictures: \(url.lastPathComponent)")
        case .failure(let error): showToast("Couldn't save the photo: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.frozen = nil
            self.counting = false
            self.updateControls()
        }
    }

    private func showToast(_ text: String) {
        toastLabel.stringValue = "  \(text)  "
        toastLabel.alphaValue = 1
        toastLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                self.toastLabel.animator().alphaValue = 0
            }, completionHandler: { self.toastLabel.isHidden = true })
        }
    }
}
