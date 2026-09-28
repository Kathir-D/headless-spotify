#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# install.sh — privileged install step (sudo ONLY here, never in the CLI).
#   1. Build (or reuse) the CLI and install it to /usr/local/bin.
#   2. `hide --skip-relaunch` as root: back up Info.plist (+ seal), set
#      LSUIElement=true, ad-hoc re-sign (credit: 4ian/hide-spotify-from-dock).
#   3. `hide --skip-plist` as the console user: relaunch headless
#      (activates:false) and verify `player state` (<=10 s default).
#   4. Install the injector dylib to /usr/local/lib/headless-spotify/.
#   5. Generate + bootstrap the watcher LaunchAgent as the console user.
#
# Usage: sudo ./install.sh [/Applications/Spotify.app]
set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
BIN="${BIN:-/usr/local/bin/headless-spotify}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "install.sh must run with sudo (it edits $SPOTIFY_APP and installs to $BIN)." >&2
  exit 1
fi
if [ -z "${SUDO_USER:-}" ]; then
  echo "install.sh must be run via sudo (not as root directly) so Spotify relaunches as you." >&2
  exit 1
fi
if [ ! -d "$SPOTIFY_APP" ]; then
  echo "error: Spotify not found at $SPOTIFY_APP" >&2
  exit 1
fi

# 1. CLI binary: explicit HEADLESS_BIN wins, then a tarball-layout bin/ next
#    to this script, then a source-tree release build, then build from source.
#    (Multi-arch `swift build` products live in .build/apple/Products/Release.)
find_built() {
  for candidate in \
    "$SCRIPT_DIR/.build/apple/Products/Release/$1" \
    "$SCRIPT_DIR/.build/release/$1"; do
    if [ -f "$candidate" ]; then echo "$candidate"; return 0; fi
  done
  found="$(find "$SCRIPT_DIR/.build" -path "*release/$1" -type f 2>/dev/null | head -1 || true)"
  [ -n "$found" ] && echo "$found" && return 0
  return 1
}
if [ -n "${HEADLESS_BIN:-}" ]; then
  install -m 0755 "$HEADLESS_BIN" "$BIN"
  echo "installed $HEADLESS_BIN -> $BIN"
elif [ -f "$SCRIPT_DIR/bin/headless-spotify" ]; then
  install -m 0755 "$SCRIPT_DIR/bin/headless-spotify" "$BIN"
  echo "installed $SCRIPT_DIR/bin/headless-spotify -> $BIN"
elif BUILT_BIN="$(find_built headless-spotify)"; then
  install -m 0755 "$BUILT_BIN" "$BIN"
  echo "installed $BUILT_BIN -> $BIN"
else
  if ! command -v swift >/dev/null 2>&1; then
    echo "error: Xcode CLT swift not found and HEADLESS_BIN unset." >&2
    exit 1
  fi
  echo "building release binary…"
  (cd "$SCRIPT_DIR" && swift build -c release)
  install -m 0755 "$SCRIPT_DIR/.build/release/headless-spotify" "$BIN"
  echo "installed $BIN"
fi

# 2. Privileged plist edit (no relaunch as root — that would own your session).
"$BIN" hide --skip-relaunch --spotify-app "$SPOTIFY_APP"

# 3. Relaunch + verify as the console user.
sudo -u "$SUDO_USER" "$BIN" hide --skip-plist --spotify-app "$SPOTIFY_APP"

# 4. Injector dylib (fallback for Dock-return when plist mode is insufficient).
DYLIB_SRC="${HEADLESS_DYLIB:-}"
if [ -z "$DYLIB_SRC" ] && [ -f "$SCRIPT_DIR/lib/libHeadlessSpotifyInjector.dylib" ]; then
  DYLIB_SRC="$SCRIPT_DIR/lib/libHeadlessSpotifyInjector.dylib"
elif [ -z "$DYLIB_SRC" ]; then
  DYLIB_SRC="$(find_built libHeadlessSpotifyInjector.dylib || true)"
fi
if [ -f "$DYLIB_SRC" ]; then
  mkdir -p /usr/local/lib/headless-spotify
  install -m 0644 "$DYLIB_SRC" /usr/local/lib/headless-spotify/
  echo "installed injector dylib"
else
  echo "warning: injector dylib not built ($DYLIB_SRC missing) — plist mode only." >&2
fi

# 5. Watcher LaunchAgent: generate from the CLI (single source of truth) and
#    bootstrap it as the console user so hiding survives updates + restarts.
USER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [ -n "$USER_HOME" ]; then
  AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
  sudo -u "$SUDO_USER" mkdir -p "$AGENTS_DIR"
  sudo -u "$SUDO_USER" "$BIN" watch --print-agent-plist --spotify-app "$SPOTIFY_APP" --interval 15 > "$AGENTS_DIR/com.headless-spotify.watcher.plist"
  chown "$SUDO_USER" "$AGENTS_DIR/com.headless-spotify.watcher.plist"
  sudo -u "$SUDO_USER" /bin/launchctl bootout "gui/$(id -u "$SUDO_USER")" "$AGENTS_DIR/com.headless-spotify.watcher.plist" 2>/dev/null || true
  sudo -u "$SUDO_USER" /bin/launchctl bootstrap "gui/$(id -u "$SUDO_USER")" "$AGENTS_DIR/com.headless-spotify.watcher.plist"
  echo "watcher agent loaded"
fi

echo "done: Spotify is headless. Verify any time with: headless-spotify status"
