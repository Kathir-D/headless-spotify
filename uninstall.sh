#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# uninstall.sh — reverse install.sh: restore the original Info.plist (+ seal,
# so Apple's signature verifies again), relaunch Spotify normally, unload and
# remove the watcher agent, remove the CLI binary.
#
# Runs as you; re-run with sudo only if the bundle is root-owned.
# Usage: ./uninstall.sh [/Applications/Spotify.app]
set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
BIN="${BIN:-/usr/local/bin/headless-spotify}"
LABEL="com.headless-spotify.watcher"

need_root() { [ ! -w "$SPOTIFY_APP/Contents/Info.plist" ] && [ "$(id -u)" -ne 0 ]; }

if [ ! -d "$SPOTIFY_APP" ]; then
  echo "error: Spotify not found at $SPOTIFY_APP" >&2
  exit 1
fi
if need_root; then
  echo "uninstall needs sudo for this root-owned bundle: sudo ./uninstall.sh $SPOTIFY_APP" >&2
  exit 1
fi

# 1. Restore original plist (+ seal); skip relaunch here…
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

# 2. Unload + remove watcher agent (best effort; absent until task 3).
for AGENTS_DIR in "$HOME/Library/LaunchAgents" /Library/LaunchAgents; do
  PLIST="$AGENTS_DIR/$LABEL.plist"
  if [ -f "$PLIST" ]; then
    UID_NUM="$(id -u)"
    launchctl bootout "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST" && echo "removed $PLIST"
  fi
done

# 3. Remove CLI binary.
if [ -f "$BIN" ] && [ -w "$(dirname "$BIN")" ]; then
  rm -f "$BIN" && echo "removed $BIN"
elif [ -f "$BIN" ]; then
  echo "keeping $BIN (not writable — remove with: sudo rm $BIN)"
fi

echo "done: Spotify Dock icon restored."
