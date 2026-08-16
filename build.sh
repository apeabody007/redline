#!/bin/bash
# Builds Redline.app. Needs only the Xcode Command Line Tools, no full Xcode.
#   ./build.sh            build into ./build
#   ./build.sh install    build, then move it to /Applications and launch it
#   ./build.sh icon       redraw Resources/Redline.icns from tools/make-icon.swift
set -euo pipefail

NAME="Redline"
BUNDLE_ID="dev.aaronpeabody.redline"
VERSION="1.0"

cd "$(dirname "$0")"
APP="build/$NAME.app"

if [[ "${1:-}" == "icon" ]]; then
  swift tools/make-icon.swift
  exit 0
fi

if [[ "${1:-}" == "test" ]]; then
  mkdir -p build/tests
  # The test file holds top-level code, so it has to be named main.swift.
  cp Tests/UnitTests.swift build/tests/main.swift
  swiftc -O Sources/Metrics.swift Sources/Sensors.swift build/tests/main.swift \
    -o build/tests/unittests
  exec build/tests/unittests
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O \
  -target "arm64-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$NAME"

cp "Resources/$NAME.icns" "$APP/Contents/Resources/$NAME.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>$NAME</string>
  <key>CFBundleIconName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Without a stable identity macOS will not keep the login
# item registration, and the window server gets fussy about the panel.
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  osascript -e 'quit app "Redline"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed to /Applications/$NAME.app and launched."
fi
