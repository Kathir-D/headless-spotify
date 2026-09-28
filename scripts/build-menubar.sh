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
#   CONFIG=debug       build the debug binary (default: release)
#   OUT_DIR=<dir>      output directory (default: dist)
#   BUILD_DIR=<dir>    package an already-built binary (skips detection)
#   SKIP_BUILD=1       reuse existing build products
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

# Which build products to package. Callers that already resolved a build dir
# (scripts/package-release.sh) pass BUILD_DIR so there is no second guess.
# Multi-arch builds land in .build/apple/Products/<Release|Debug> (capitalised);
# single-arch builds in .build/<triple>/<config> (lowercase). Both exist
# depending on the toolchain, so check them explicitly.
case "$CONFIG" in
  release) PRODUCTS_CONFIG="Release" ;;
  debug)   PRODUCTS_CONFIG="Debug" ;;
  *)       PRODUCTS_CONFIG="$CONFIG" ;;
esac
if [ -n "${BUILD_DIR:-}" ] && [ -f "$BUILD_DIR/$EXECUTABLE" ]; then
  :
else
  BUILD_DIR=""
  for candidate in \
    "$SCRIPT_DIR/.build/apple/Products/$PRODUCTS_CONFIG" \
    "$SCRIPT_DIR/.build/$CONFIG"; do
    if [ -f "$candidate/$EXECUTABLE" ]; then
      BUILD_DIR="$candidate"
      break
    fi
  done
  if [ -z "$BUILD_DIR" ]; then
    # Last resort, and deliberately strict. A bare `find -name` also matches
    # SwiftPM intermediates (.build/**/Intermediates.noindex/.../Binary/) and
    # dSYM payloads — all of which are Mach-O files that are NOT the product.
    # Only accept the executable sitting directly in a products directory or
    # in a per-triple <config> directory.
    for pattern in \
      ".*/Products/$PRODUCTS_CONFIG/$EXECUTABLE" \
      ".*/$CONFIG/$EXECUTABLE" \
      ".*/Products/[^/]+/$EXECUTABLE" \
      ".*/(release|Release)/$EXECUTABLE"; do
      CANDIDATE="$(find "$SCRIPT_DIR/.build" -type f -regex "$pattern" 2>/dev/null | head -1 || true)"
      if [ -n "$CANDIDATE" ]; then
        BUILD_DIR="$(dirname "$CANDIDATE")"
        break
      fi
    done
  fi
fi
if [ -z "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/$EXECUTABLE" ]; then
  echo "error: could not find a built $EXECUTABLE under $SCRIPT_DIR/.build (build failed?)" >&2
  exit 1
fi
echo "binary from $BUILD_DIR"

APP="$OUT_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"
# Never ship a stub, an object file, or an empty file as the executable.
if ! /usr/bin/file "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null | grep -q "Mach-O"; then
  echo "error: $BUILD_DIR/$EXECUTABLE is not a Mach-O executable — refusing to package it" >&2
  rm -rf "$APP"
  exit 1
fi

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
