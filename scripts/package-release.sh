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

# Guard against shipping a single-arch tarball: every artifact must contain
# exactly the architectures we asked for. A silent arm64-only release is the
# kind of bug nobody notices until a user's Intel/ARM mismatch.
WANT_ARCHS="$(echo $ARCHS | tr ' ' '\n' | sort | tr '\n' ' ')"
check_archs() { # check_archs <path> <label>
  got="$(lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ "$got" != "$WANT_ARCHS" ]; then
    echo "error: $2 archs are [$got], expected [$WANT_ARCHS]" >&2
    exit 1
  fi
  echo "ok: $2 is [$got]"
}
check_archs "$BUILD_DIR/headless-spotify" "headless-spotify"
check_archs "$BUILD_DIR/libHeadlessSpotifyInjector.dylib" "injector dylib"
check_archs "$BUILD_DIR/headless-spotify-bar" "headless-spotify-bar"

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
# + BUILD_DIR reuse exactly the products staged above (universal when
# multi-arch) instead of re-detecting a build directory. DYLIB names the
# injector explicitly: build-menubar.sh only builds the bar binary, so left to
# its own search it would not find a dylib in a single-arch .build/<triple>/.
SKIP_BUILD=1 BUILD_DIR="$BUILD_DIR" DYLIB="$BUILD_DIR/libHeadlessSpotifyInjector.dylib" \
  ./scripts/build-menubar.sh >/dev/null
if [ -d "dist/headless-spotify.app" ]; then
  cp -R "dist/headless-spotify.app" "$STAGE/"
else
  echo "warning: menu bar app not built — tarball ships the CLI only" >&2
fi

# The Homebrew cask moves the .app into /Applications and nothing else, so
# everything the privileged step needs has to be inside the bundle. A glob that
# quietly matches nothing ships a release whose install.sh is unreachable, with
# nothing in the build output to say so — assert the files are really there.
for bundled in \
  Contents/MacOS/headless-spotify-bar \
  Contents/Resources/install.sh \
  Contents/Resources/uninstall.sh \
  Contents/Resources/lib/libHeadlessSpotifyInjector.dylib; do
  if [ ! -e "$STAGE/headless-spotify.app/$bundled" ]; then
    echo "error: $bundled is missing from the app bundle" >&2
    exit 1
  fi
done
# install.sh has to arrive executable, or `sudo .../install.sh` fails with a
# permission error that reads like a broken download.
for exec_bit in Contents/Resources/install.sh Contents/Resources/uninstall.sh; do
  if [ ! -x "$STAGE/headless-spotify.app/$exec_bit" ]; then
    echo "error: $exec_bit is not executable in the app bundle" >&2
    exit 1
  fi
done
# A resource added after the ad-hoc signature invalidates the seal, and macOS
# then refuses to launch the app at all — which would be a silent regression,
# because the bundle still exists and still looks fine.
if ! /usr/bin/codesign --verify --strict "$STAGE/headless-spotify.app" >/dev/null 2>&1; then
  echo "error: codesign --verify fails on the app bundle — a resource was added after signing?" >&2
  exit 1
fi
echo "ok: app bundle carries install.sh, uninstall.sh, the dylib, and verifies"

TARBALL="dist/headless-spotify-$VERSION-macos.tar.gz"
tar -czf "$TARBALL" -C dist/stage "headless-spotify-$VERSION"
(cd dist && shasum -a 256 "$(basename "$TARBALL")" > SHA256SUMS.txt)

echo "wrote $TARBALL"
cat dist/SHA256SUMS.txt
echo "publish: gh release create v$VERSION $TARBALL dist/SHA256SUMS.txt --title v$VERSION"
