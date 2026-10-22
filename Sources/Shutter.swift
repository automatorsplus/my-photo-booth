import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Countdown beeps, played the way Photo Booth's PBNotePlayer does: a General MIDI
/// instrument (program 35) from the system sound bank, pitch 80, velocity 115, 0.4 s long.
final class CountdownChime {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        try? sampler.loadSoundBankInstrument(at: bank, program: 35,
                                             bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                             bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        try? engine.start()
    }

    func beep() {
        if !engine.isRunning { try? engine.start() }
        sampler.startNote(80, withVelocity: 115, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [sampler] in
            sampler.stopNote(80, onChannel: 0)
        }
    }
}

/// The screen flash and shutter sound.
enum Flash {
    /// Photo Booth's default flash calls CGDisplayVisualBell with (0.04, 0.2, 0.24, 1.0),
    /// read here as fade-in, hold and fade-out seconds at full intensity. It also raises every
    /// display to full brightness through a private framework, which this version skips.
    static let fadeIn = 0.04, hold = 0.2, fadeOut = 0.24

    private static var windows: [NSWindow] = []

    static func fire() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .white
            window.isOpaque = false
            window.alphaValue = 0
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            return window
        }
        let flashing = windows
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeIn
            flashing.forEach { $0.animator().alphaValue = 1 }
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = fadeOut
                    flashing.forEach { $0.animator().alphaValue = 0 }
                }, completionHandler: {
                    flashing.forEach { $0.orderOut(nil) }
                })
            }
        })
    }

    /// Photo Booth plays system sound ID 24 here; which sound that maps to wasn't established,
    /// so this plays macOS's own camera shutter sound.
    static func playShutterSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif"
        (NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink"))?.play()
    }
}

/// Writes photos to ~/Pictures with Photo Booth's naming: "Photo on <date> at <time>.jpg",
/// with "/" turned into "-" and ":" into ".", and " #2", " #3"… when the name is taken.
enum PhotoSaver {
    static func save(_ image: CGImage, date: Date = Date(), in folder: URL? = nil) throws -> URL {
        guard let pictures = folder ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let day = formatter.string(from: date)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        let base = "Photo on \(day) at \(time)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")

        var url = pictures.appendingPathComponent(base + ".jpg")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = pictures.appendingPathComponent("\(base) #\(n).jpg")
            n += 1
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
