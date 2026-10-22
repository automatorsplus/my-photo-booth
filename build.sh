#!/bin/zsh
# Builds build/MyPhotoBooth.app.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID=local.myphotobooth
APP=build/MyPhotoBooth.app

# Assemble and sign outside this folder: iCloud Drive keeps adding Finder metadata to
# bundles in synced folders such as the Desktop, and codesign refuses to sign a bundle that carries it.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
STAGED="$STAGE/MyPhotoBooth.app"
mkdir -p "$STAGED/Contents/MacOS"
cp Info.plist "$STAGED/Contents/Info.plist"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/*.swift \
  -o "$STAGED/Contents/MacOS/MyPhotoBooth"

xattr -cr "$STAGED"

# Ad-hoc signature with an identifier-only designated requirement, so the camera
# permission is tied to the bundle ID rather than to this exact build.
codesign --force --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" "$STAGED"

rm -rf "$APP"
mkdir -p build
ditto "$STAGED" "$APP"

echo "Built $PWD/$APP"
