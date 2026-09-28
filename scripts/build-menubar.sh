#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# build-menubar.sh — build the menu bar extra and package it as an
# LSUIElement .app (no Dock icon, no Cmd-Tab entry).
#
# The app itself is deliberately tiny: an SF Symbol in the menu bar whose
# menu shows the project name and a single Quit action. VERSION is copied
# into Info.plist so the menu shows the same version as `headless-spotify`.
#
# Output: dist/headless-spotify.app  (ad-hoc signed)
#
# Usage: ./scripts/build-menubar.sh
#   CONFIG=debug      build the debug binary (default: release)
#   OUT_DIR=<dir>     output directory (default: dist)
#   SKIP_BUILD=1      reuse existing build products
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="$(tr -d ' \t\r\n' < VERSION)"
CONFIG="${CONFIG:-release}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/dist}"
APP_NAME="headless-spotify"
BUNDLE_ID="com.headless-spotify.bar"
EXECUTABLE="headless-spotify-bar"

if [ -z "${SKIP_BUILD:-}" ]; then
  echo "building menu bar extra ($CONFIG)…"
  swift build -c "$CONFIG" --product "$EXECUTABLE"
fi

# Multi-arch builds land in .build/apple/Products/<Config>; single-arch in
# .build/<triple>/<config>. Detect whichever swift just produced.
BUILD_DIR="$SCRIPT_DIR/.build/$CONFIG"
if [ ! -f "$BUILD_DIR/$EXECUTABLE" ]; then
  CANDIDATE="$(find "$SCRIPT_DIR/.build" -path "*Products/$CONFIG/$EXECUTABLE" -type f 2>/dev/null | head -1 || true)"
  if [ -z "$CANDIDATE" ]; then
    CANDIDATE="$(find "$SCRIPT_DIR/.build" -path "*$CONFIG/$EXECUTABLE" -type f 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$CANDIDATE" ]; then BUILD_DIR="$(dirname "$CANDIDATE")"; fi
fi
if [ ! -f "$BUILD_DIR/$EXECUTABLE" ]; then
  echo "error: $BUILD_DIR/$EXECUTABLE not found (build failed?)" >&2
  exit 1
fi
echo "binary from $BUILD_DIR"

APP="$OUT_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT (c) 2026 headless-spotify Contributors</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 \
  || echo "warning: ad-hoc signing failed (the app still runs locally)" >&2

echo "wrote $APP (v$VERSION)"
echo "run it with: open \"$APP\""
