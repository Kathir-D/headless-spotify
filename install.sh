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

# 1. CLI binary: reuse HEADLESS_BIN when provided (release tarballs), else build.
if [ -n "${HEADLESS_BIN:-}" ]; then
  install -m 0755 "$HEADLESS_BIN" "$BIN"
  echo "installed $HEADLESS_BIN -> $BIN"
elif [ -x "$BIN" ] && [ "$SCRIPT_DIR/.build/release/headless-spotify" -ot "$BIN" ] 2>/dev/null; then
  echo "reusing $BIN"
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
DYLIB_SRC="$SCRIPT_DIR/.build/release/libHeadlessSpotifyInjector.dylib"
if [ -n "${HEADLESS_DYLIB:-}" ]; then
  DYLIB_SRC="$HEADLESS_DYLIB"
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
