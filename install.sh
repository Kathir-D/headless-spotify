#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# install.sh — task 1 stub.
# Task 2 will: back up Info.plist, `defaults write ... LSUIElement true`,
# restart Spotify headless, and poll `player state` (<=10 s).
#
# Usage: sudo ./install.sh [/Applications/Spotify.app]
# sudo is required ONLY here (writing Spotify.app's Info.plist).
set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
PLIST="$SPOTIFY_APP/Contents/Info.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "install.sh must run with sudo (it edits $PLIST)." >&2
  exit 1
fi

if [ ! -f "$PLIST" ]; then
  echo "error: Spotify not found at $SPOTIFY_APP" >&2
  exit 1
fi

echo "headless-spotify install (task 1 stub): no changes made."
echo "Task 2 implements: backup $PLIST, set LSUIElement=true, relaunch headless."
