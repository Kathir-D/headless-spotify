#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# package-release.sh — build the versioned release tarball + checksums.
# VERSION is the source of truth; the git tag must be v$(cat VERSION).
#
# Output: dist/headless-spotify-<version>-macos.tar.gz + dist/SHA256SUMS.txt
#
# Usage: ./scripts/package-release.sh
#   PACKAGE_ARCHS="arm64 x86_64"   (default; space-separated swift --arch values)
#   SKIP_BUILD=1                   (reuse the existing .build/release products)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="$(tr -d ' \t\r\n' < VERSION)"
CLI_VERSION="$(sed -n 's/.*public static let version = "\(.*\)".*/\1/p' Sources/HeadlessSpotify/CLI.swift | head -1)"
if [ "$VERSION" != "$CLI_VERSION" ]; then
  echo "error: VERSION ($VERSION) != CLI.version ($CLI_VERSION)" >&2
  exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "building for existing tag v$VERSION"
else
  echo "note: tag v$VERSION does not exist yet — create it after this passes:"
  echo "  git tag -a v$VERSION -m \"headless-spotify v$VERSION\""
fi

ARCHS="${PACKAGE_ARCHS:-arm64 x86_64}"
# Multi-arch builds land in .build/apple/Products/Release; single-arch in
# .build/<triple>/release. Detect whichever swift just produced.
BUILD_DIR="$SCRIPT_DIR/.build/release"
if [ -z "${SKIP_BUILD:-}" ]; then
  ARCH_FLAGS=""
  # shellcheck disable=SC2086
  for arch in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done
  echo "building release ($ARCHS)…"
  # shellcheck disable=SC2086
  swift build -c release $ARCH_FLAGS
  if [ -f "$SCRIPT_DIR/.build/apple/Products/Release/headless-spotify" ]; then
    BUILD_DIR="$SCRIPT_DIR/.build/apple/Products/Release"
  else
    CANDIDATE="$(find "$SCRIPT_DIR/.build" -path '*release/headless-spotify' -type f 2>/dev/null | head -1 || true)"
    if [ -n "$CANDIDATE" ]; then BUILD_DIR="$(dirname "$CANDIDATE")"; fi
  fi
else
  for candidate in "$SCRIPT_DIR/.build/apple/Products/Release" "$SCRIPT_DIR/.build/release"; do
    if [ -f "$candidate/headless-spotify" ]; then BUILD_DIR="$candidate"; break; fi
  done
fi
echo "products from $BUILD_DIR"
for artifact in headless-spotify libHeadlessSpotifyInjector.dylib; do
  if [ ! -f "$BUILD_DIR/$artifact" ]; then
    echo "error: missing $BUILD_DIR/$artifact (build failed?)" >&2
    exit 1
  fi
done

STAGE="dist/stage/headless-spotify-$VERSION"
rm -rf "dist/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/launchagent"
cp "$BUILD_DIR/headless-spotify" "$STAGE/bin/"
cp "$BUILD_DIR/libHeadlessSpotifyInjector.dylib" "$STAGE/lib/"
cp install.sh uninstall.sh LICENSE README.md THIRD-PARTY-NOTICES.md VERSION "$STAGE/"
cp launchagent/com.headless-spotify.watcher.plist "$STAGE/launchagent/"
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh"

# Menu bar extra as a ready-to-install LSUIElement .app at the tarball root,
# so install.sh can drop it in /Applications without a toolchain. SKIP_BUILD
# keeps whatever `swift build` just produced (universal when multi-arch).
SKIP_BUILD=1 ./scripts/build-menubar.sh >/dev/null
if [ -d "dist/headless-spotify.app" ]; then
  cp -R "dist/headless-spotify.app" "$STAGE/"
else
  echo "warning: menu bar app not built — tarball ships the CLI only" >&2
fi

TARBALL="dist/headless-spotify-$VERSION-macos.tar.gz"
tar -czf "$TARBALL" -C dist/stage "headless-spotify-$VERSION"
(cd dist && shasum -a 256 "$(basename "$TARBALL")" > SHA256SUMS.txt)

echo "wrote $TARBALL"
cat dist/SHA256SUMS.txt
echo "publish: gh release create v$VERSION $TARBALL dist/SHA256SUMS.txt --title v$VERSION"
