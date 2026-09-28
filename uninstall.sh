#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# uninstall.sh — task 1 stub.
# Task 2 will: restore the Info.plist backup and relaunch Spotify normally.
#
# Usage: ./uninstall.sh [/Applications/Spotify.app]   (no sudo needed unless restoring root-owned files)
set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
PLIST="$SPOTIFY_APP/Contents/Info.plist"

echo "headless-spotify uninstall (task 1 stub): no changes made."
echo "Task 2 implements: restore $PLIST backup, relaunch Spotify with Dock icon."
