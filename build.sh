#!/bin/bash
# Builds Lantern.app. Requires the Xcode Command Line Tools; no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Lantern"
BUNDLE_ID="com.dominic.lantern"
VERSION="1.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Compiling"
swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos13.0 \
  -framework AppKit -framework IOKit -framework ServiceManagement \
  -framework Speech -framework AVFoundation -framework Accelerate \
  -o "$MACOS_DIR/$APP_NAME" \
  Sources/*.swift

echo "==> Compiling charge-key probe"
swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos13.0 \
  -framework IOKit \
  -o "$BUILD_DIR/lantern-probe" \
  Sources/SMC.swift Probe/main.swift

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Menu-bar accessory: no Dock icon, no main menu. -->
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Lantern listens for the Oath of the Lantern to unseal charging. Recognition runs entirely on this Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Lantern recognises the Oath of the Lantern on-device. No audio leaves this Mac.</string>
</dict>
</plist>
PLIST

echo "==> Rendering icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
PNGS="$BUILD_DIR/icon-png"
"$MACOS_DIR/$APP_NAME" --export-icon "$PNGS"
mkdir -p "$ICONSET"
cp "$PNGS/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$PNGS/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$PNGS/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$PNGS/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$PNGS/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$PNGS/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$PNGS/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$PNGS/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$PNGS/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$PNGS/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET" "$PNGS"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo
echo "Built $APP"
echo "Built $BUILD_DIR/lantern-probe  (charge-key probe; run with sudo while charging)"
echo "Run it with:  open \"$(pwd)/$APP\""
