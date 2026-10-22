# MyPhotoBooth

Your webcam with Photo Booth's 24 effects, a 3·2·1 countdown, a screen flash, and the photo saved to your Pictures folder. The effects reuse the filter chains and numbers read out of Photo Booth itself.

## Set it up with Claude Code

Open Claude Code in the folder where you keep your projects and paste:

```
Clone https://github.com/automatorsplus/my-photo-booth and set it up on my Mac by following its CLAUDE.md.
```

Claude Code builds the app, checks every effect renders and walks you through the camera permission. It needs an Apple Silicon Mac on macOS 13 or later. The app is built on your own Mac, so macOS doesn't block it as a download from an unknown developer.

## Requirements

- Apple Silicon Mac, macOS 13 or later
- Xcode Command Line Tools (`swiftc`)

## Build and run by hand

```sh
./build.sh
open build/MyPhotoBooth.app
```

Allow camera access the first time. If you said no, turn on MyPhotoBooth under System Settings → Privacy & Security → Camera, then reopen it.

## Use

- **Effects** shows a 3×3 grid of live previews with Normal in the middle. Use ◀ ▶, or the arrow keys, to change page, then click a tile to pick it. The pages are faces, colours and distortions, in Photo Booth's order.
- For **Bulge, Dent, Twirl, Squeeze and Light Tunnel**, click or drag on the picture to move the centre. The slider sets the strength.
- The face effects (Space Alien, Bug Out, Lovestruck and the rest) follow your face. If no face is found you'll see the plain picture.
- The red **shutter button**, Space or ⌘T takes a photo: 0.5 s, then 3, 2, 1 with a beep each, 0.8 s apart. Then the picture freezes, the screen flashes white, and the shutter sounds. Esc cancels during the countdown.
- Photos are saved as `~/Pictures/Photo on 16-10-2026 at 14.32.jpg`. A second photo in the same minute gets ` #2`. A note at the top of the window shows the name.
- The preview is mirrored, like Photo Booth. The photo is saved as you saw it. To save un-mirrored photos, turn on **Camera → Save Photos Unmirrored**.
- **Camera → Show Photos in Finder** opens your Pictures folder.

## Checking the effects without a camera

```sh
build/MyPhotoBooth.app/Contents/MacOS/MyPhotoBooth --render some-photo.jpg out/
```

This writes every effect applied to the photo, plus the three grid pages, as PNGs. It needs no permissions. If the photo has no face, the face effects use a stand-in face in the middle.

## How it differs from Photo Booth

- **Face tracking**: Photo Booth uses a private Vision tracker. This uses the public face-landmarks request.
- **Artwork**: hearts, birds, pencil noise and colour ramps are drawn in code. Apple's image files aren't copied.
- **Lovestruck and Dizzy**: the motion is an approximation.
- **Brightness**: Photo Booth also turns every display to full brightness for the flash, through a private framework. This doesn't.
- **Shutter sound**: the shutter sound is macOS's own, since the sound Photo Booth plays wasn't identified.
- **Originals**: photos go straight into Pictures, with no library and no unfiltered copy.

## Files

| File | What it does |
|---|---|
| `Sources/Effects.swift` | The 24 effects and their Photo Booth constants |
| `Sources/Kernels.swift` | Edge mirroring, Fish Eye and Stretch kernels |
| `Sources/FaceTracker.swift` | Vision face landmarks, smoothed, in the shape of Photo Booth's `PBFace` |
| `Sources/EffectGrid.swift` | The 3×3 live preview page |
| `Sources/BoothController.swift` | Window, controls, countdown and capture |
| `Sources/Shutter.swift` | Countdown beeps, flash, shutter sound and saving |
| `Sources/Camera.swift` | Webcam frames |
| `Sources/Sprites.swift` | Heart and bird drawings |
