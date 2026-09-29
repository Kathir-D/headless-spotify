#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# check-cask-install.sh — install the staged cask and assert what a user
# actually gets.
#
# A cask has no `test do` block, so this is where the checks the old formula's
# test block used to make live. It is deliberately an end-to-end check rather
# than a file-existence check: the bug it guards against was "brew install
# succeeded and there was no app", which only an install can reproduce.
#
# Usage: ./scripts/check-cask-install.sh <owner>/<tap>/<cask>
set -eu

CASK="${1:?usage: check-cask-install.sh <owner>/<tap>/<cask>}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/headless-spotify.app"

HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "$CASK"

# The whole point of the cask: the bundle is in /Applications, not a Cellar.
if [ ! -d "$APP" ]; then
  echo "error: $APP is missing after brew install --cask" >&2
  exit 1
fi

# LSUIElement, so the extra has no Dock icon and no Cmd-Tab entry of its own.
LSUI="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$LSUI" != "true" ]; then
  echo "error: LSUIElement is '$LSUI', expected true" >&2
  exit 1
fi

# The privileged step has to be findable at a path that does not change between
# versions, or the cask installs an app that does nothing and no instructions.
for helper in install.sh uninstall.sh lib/libHeadlessSpotifyInjector.dylib; do
  if [ ! -e "$APP/Contents/Resources/$helper" ]; then
    echo "error: $APP/Contents/Resources/$helper is missing" >&2
    exit 1
  fi
done
if [ ! -x "$APP/Contents/Resources/install.sh" ]; then
  echo "error: $APP/Contents/Resources/install.sh is not executable" >&2
  exit 1
fi

# Still ad-hoc signed. A resource added after signing invalidates the seal, and
# macOS then refuses to launch the app — a silent regression, because the
# bundle is still there and still looks fine.
if ! /usr/bin/codesign --verify --strict "$APP" >/dev/null 2>&1; then
  echo "error: codesign --verify fails on $APP — a resource was added after signing?" >&2
  exit 1
fi

# The CLI, on PATH, at the version this build produced and nowhere else — a
# second copy under /usr/local/bin is the one thing the cask must not cause.
VERSION="$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")"
if ! command -v headless-spotify >/dev/null 2>&1; then
  echo "error: headless-spotify is not on PATH after the cask install" >&2
  exit 1
fi
if ! headless-spotify --version | grep -q "$VERSION"; then
  echo "error: 'headless-spotify --version' does not report $VERSION" >&2
  exit 1
fi
if [ -e /usr/local/bin/headless-spotify ] && [ ! -L /usr/local/bin/headless-spotify ]; then
  echo "error: /usr/local/bin/headless-spotify is a real file; the cask should not install one" >&2
  exit 1
fi

# And it runs. An LSUIElement app has to actually reach the menu bar, which
# "the process exists" is the closest a CI runner can get to proving.
sleep 2
if ! pgrep -f headless-spotify-bar >/dev/null 2>&1; then
  echo "error: the menu bar extra is not running after the postflight launch" >&2
  exit 1
fi

echo "ok: $APP installed, LSUIElement set, helpers bundled, CLI on PATH, menu bar extra running"
