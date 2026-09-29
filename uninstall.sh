#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# uninstall.sh — reverse install.sh: stop the watcher and the menu bar app
# FIRST (so nothing can re-hide Spotify mid-uninstall), then restore the
# original Info.plist (+ seal, so Apple's signature verifies again), relaunch
# Spotify normally, and remove the agent, the app and the CLI.
#
# Runs as you; re-run with sudo only if the bundle is root-owned.
# Usage: ./uninstall.sh [/Applications/Spotify.app]
set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
BIN="${BIN:-/usr/local/bin/headless-spotify}"
LABEL="com.headless-spotify.watcher"

# install.sh reuses a headless-spotify that is already on PATH rather than
# installing a second copy (that is the Homebrew cask layout, where
# $(brew --prefix)/bin is /usr/local/bin on Intel). Resolve it the same way, so
# `restore` below finds the same binary install.sh used.
if [ ! -x "$BIN" ]; then
  if PATH_BIN="$(command -v headless-spotify 2>/dev/null || true)" && [ -n "$PATH_BIN" ]; then
    BIN="$PATH_BIN"
  fi
fi

need_root() { [ ! -w "$SPOTIFY_APP/Contents/Info.plist" ] && [ "$(id -u)" -ne 0 ]; }

# Relaunching Spotify as root would start it in root's session, not yours.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
  echo "uninstall must run via sudo (as you), not as root directly, so Spotify relaunches for your user." >&2
  exit 1
fi

if [ ! -d "$SPOTIFY_APP" ]; then
  echo "error: Spotify not found at $SPOTIFY_APP" >&2
  exit 1
fi
if need_root; then
  echo "uninstall needs sudo for this root-owned bundle: sudo ./uninstall.sh $SPOTIFY_APP" >&2
  exit 1
fi

# The watcher belongs to the console user. Under sudo, `id -u` is 0 and $HOME
# may be root's, so resolve both from SUDO_USER — otherwise bootout targets
# root's GUI domain and the watcher keeps running (and re-hiding Spotify).
GUI_USER="${SUDO_USER:-$(id -un)}"
GUI_UID="$(id -u "$GUI_USER")"
USER_HOME="$(dscl . -read "/Users/$GUI_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
USER_HOME="${USER_HOME:-$HOME}"

# 1. Stop everything that could re-hide Spotify FIRST. The watcher polls every
#    few seconds, so restoring the plist while it is still loaded can be undone
#    by it before we get to step 2. Uninstall order is the safety property.
for AGENTS_DIR in "$USER_HOME/Library/LaunchAgents" /Library/LaunchAgents; do
  PLIST="$AGENTS_DIR/$LABEL.plist"
  if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$GUI_UID" "$PLIST" 2>/dev/null || true
    echo "stopped watcher $PLIST"
  fi
done
pkill -f "headless-spotify watch" 2>/dev/null || true

# 2. Restore original plist (+ seal); skip relaunch here…
if [ -x "$BIN" ]; then
  "$BIN" restore --skip-relaunch --spotify-app "$SPOTIFY_APP" || true
  # …then relaunch normally as the console user (never as root).
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" "$BIN" restore --skip-plist --spotify-app "$SPOTIFY_APP" || true
  else
    "$BIN" restore --skip-plist --spotify-app "$SPOTIFY_APP" || true
  fi
else
  echo "warning: $BIN not found — skipping relaunch (restore the backup manually if needed)." >&2
fi

# 3. Remove the watcher agent files (already unloaded above).
for AGENTS_DIR in "$USER_HOME/Library/LaunchAgents" /Library/LaunchAgents; do
  PLIST="$AGENTS_DIR/$LABEL.plist"
  if [ -f "$PLIST" ]; then
    rm -f "$PLIST" && echo "removed $PLIST"
  fi
done

# 4. Remove the menu bar app (quit it first so it is not left running).
MENUBAR_APP="/Applications/headless-spotify.app"
if [ -d "$MENUBAR_APP" ]; then
  pkill -f headless-spotify-bar 2>/dev/null || true
  if [ -w "$MENUBAR_APP" ]; then
    rm -rf "$MENUBAR_APP" && echo "removed $MENUBAR_APP"
  else
    echo "keeping $MENUBAR_APP (not writable — remove with sudo)"
  fi
fi

# 5. Remove CLI binary + injector dylib.
#
#    A symlink is left alone. That is what a Homebrew cask installs into
#    $(brew --prefix)/bin, and removing it by hand would leave the cask
#    believing its binary is still there while `brew upgrade` no longer
#    refreshes it. `brew uninstall --cask` owns that link.
if [ -L "$BIN" ]; then
  echo "leaving $BIN — it is a Homebrew link; remove it with: brew uninstall --cask headless-spotify"
elif [ -f "$BIN" ] && [ -w "$(dirname "$BIN")" ]; then
  rm -f "$BIN" && echo "removed $BIN"
elif [ -f "$BIN" ]; then
  echo "keeping $BIN (not writable — remove with: sudo rm $BIN)"
fi
if [ -d /usr/local/lib/headless-spotify ] && [ -w /usr/local/lib/headless-spotify ]; then
  rm -rf /usr/local/lib/headless-spotify && echo "removed /usr/local/lib/headless-spotify"
elif [ -d /usr/local/lib/headless-spotify ]; then
  echo "keeping /usr/local/lib/headless-spotify (not writable — remove with sudo)"
fi

rm -f /tmp/headless-spotify-watcher.log 2>/dev/null || true

echo "done: Spotify Dock icon restored."
