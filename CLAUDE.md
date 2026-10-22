# Setting up MyPhotoBooth

You are setting up MyPhotoBooth, a webcam app for macOS with Photo Booth's 24 effects, a 3·2·1 countdown and photos
saved to the Pictures folder, on the user's Mac. Work through the steps in order. Tell the user in one line what each
step is doing. Don't change the source code unless the build fails, and then change as little as possible and say what
you changed.

## 1. Check the Mac

- `uname -m` must print `arm64` (Apple Silicon) and `sw_vers -productVersion` must be 13 or higher. If not, stop and tell
  the user MyPhotoBooth needs an Apple Silicon Mac on macOS 13 or later.
- `xcode-select -p` must print a path. If it fails, run `xcode-select --install`, ask the user to click **Install** in
  the dialog, and wait until they say it has finished.

Nothing else is needed: no Homebrew, no Xcode.

## 2. Build

```sh
./build.sh
```

It prints `Built …/build/MyPhotoBooth.app`.

## 3. Check the effects work

This needs no camera and no permissions:

```sh
sips -s format jpeg /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/UserIcon.icns --out /tmp/mpb-test.jpg
build/MyPhotoBooth.app/Contents/MacOS/MyPhotoBooth --render /tmp/mpb-test.jpg /tmp/mpb-test
ls /tmp/mpb-test | wc -l
```

It writes 28 PNGs: Normal, the 24 effects and the three grid pages. If it errors or writes fewer, fix that before
going on.

## 4. Install and open

Ask the user whether to copy the app into Applications. If yes:

```sh
cp -R build/MyPhotoBooth.app /Applications/
open /Applications/MyPhotoBooth.app
```

Otherwise `open build/MyPhotoBooth.app`. Tell the user to click **Allow** when macOS asks for the camera.

## 5. Hand over

Tell the user, briefly:

- **Effects** shows a grid of live previews; the arrows change page, a click picks one.
- The red shutter button, Space or ⌘T takes a photo after a 3·2·1 countdown. Photos go to the Pictures folder.
- For Bulge, Dent, Twirl, Squeeze and Light Tunnel, click or drag on the picture to move the centre.
- If the camera was refused: System Settings → Privacy & Security → Camera, turn on MyPhotoBooth, then reopen it.
