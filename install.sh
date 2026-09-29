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
#   5. Install + launch the menu bar extra (/Applications/headless-spotify.app).
#      Skipped when the app is already there — `brew install --cask` owns it.
#   6. Generate + bootstrap the watcher LaunchAgent as the console user
#      (skipped when hiding failed — a watcher with nothing to do would only
#      quit and relaunch a healthy Spotify).
#
# Under Homebrew the cask has already done steps 4 and 5 by the time you get
# here; what is left is the one thing that needs root — the bundle edit. Run it
# from wherever it landed:
#   sudo /Applications/headless-spotify.app/Contents/Resources/install.sh
#
# Usage: sudo ./install.sh [/Applications/Spotify.app]
#   INSTALL_MENUBAR=0   skip step 5 (CLI only).
#   KEEP_ON_FAILURE=1   if hiding fails, keep LSUIElement set instead of rolling back.
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
#    to this script, then a Homebrew prefix bin/ beside share/headless-spotify,
#    then a headless-spotify already on PATH, then a source-tree release build,
#    then build from source.
#    Multi-arch `swift build` products live in .build/apple/Products/Release
#    (capitalised) while single-arch ones land in .build/<triple>/release.
find_built() {
  for candidate in \
    "$SCRIPT_DIR/.build/apple/Products/Release/$1" \
    "$SCRIPT_DIR/.build/release/$1" \
    "$SCRIPT_DIR/.build/arm64-apple-macosx/release/$1" \
    "$SCRIPT_DIR/.build/x86_64-apple-macosx/release/$1"; do
    if [ -f "$candidate" ]; then echo "$candidate"; return 0; fi
  done
  # Restricted fallback: only real products. A bare `find -name` also matches
  # SwiftPM intermediates and dSYM payloads, which are not runnable.
  found="$(find "$SCRIPT_DIR/.build" -type f -name "$1" \
    \( -path "*Products/*" -o -path "*/release/*" -o -path "*/Release/*" \) 2>/dev/null \
    | head -1 || true)"
  if [ -n "$found" ]; then echo "$found"; return 0; fi
  return 1
}
if [ -n "${HEADLESS_BIN:-}" ]; then
  install -m 0755 "$HEADLESS_BIN" "$BIN"
  echo "installed $HEADLESS_BIN -> $BIN"
elif [ -f "$SCRIPT_DIR/bin/headless-spotify" ]; then
  install -m 0755 "$SCRIPT_DIR/bin/headless-spotify" "$BIN"
  echo "installed $SCRIPT_DIR/bin/headless-spotify -> $BIN"
elif [ -f "$SCRIPT_DIR/../bin/headless-spotify" ] || [ -f "$SCRIPT_DIR/../../bin/headless-spotify" ]; then
  # Homebrew layout: share/headless-spotify/install.sh next to <prefix>/bin.
  BREW_BIN="$(cd "$SCRIPT_DIR/../.." && pwd)/bin/headless-spotify"
  if [ -f "$BREW_BIN" ]; then
    install -m 0755 "$BREW_BIN" "$BIN"
    echo "installed $BREW_BIN -> $BIN"
  else
    echo "error: expected $BREW_BIN next to this script, but it is missing." >&2
    exit 1
  fi
elif PATH_BIN="$(command -v headless-spotify 2>/dev/null || true)"; [ -n "$PATH_BIN" ]; then
  # Already installed and on PATH, which is the Homebrew cask layout: the cask
  # links its binary into $(brew --prefix)/bin. On Intel that is
  # /usr/local/bin, i.e. exactly $BIN — so installing here would overwrite the
  # package manager's own link and leave a file `brew uninstall` does not know
  # about. Use it where it is instead.
  BIN="$PATH_BIN"
  echo "using the headless-spotify already on PATH: $BIN"
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

# 3. Relaunch + verify as the console user. Hiding can legitimately fail —
#    Spotify >= 1.3.1 quits whenever LSUIElement=true is present — so this must
#    NOT abort the install and must NOT leave Spotify unable to launch.
HIDE_OK=1
sudo -u "$SUDO_USER" "$BIN" hide --skip-plist --spotify-app "$SPOTIFY_APP" || HIDE_OK=0
if [ "$HIDE_OK" -eq 0 ]; then
  echo "" >&2
  echo "install: hiding did not verify (Spotify >= 1.3.1 quits when LSUIElement" >&2
  echo "install: is set). The CLI, dylib and menu bar app are still installed" >&2
  echo "install: and working, and Spotify is left exactly as it was." >&2
  if [ "${KEEP_ON_FAILURE:-0}" = "1" ]; then
    echo "install: LSUIElement left in place (KEEP_ON_FAILURE=1) — Spotify may not launch." >&2
    echo "install: undo with: headless-spotify restore" >&2
  else
    echo "install: rolling Info.plist back so Spotify keeps launching…" >&2
    "$BIN" restore --skip-relaunch --spotify-app "$SPOTIFY_APP" || true
    sudo -u "$SUDO_USER" /usr/bin/open -a "$SPOTIFY_APP" 2>/dev/null || true
    echo "install: Spotify restored to normal (Dock icon back). Re-run 'headless-spotify hide'" >&2
    echo "install: any time — see README 'Current status' if hiding is blocked." >&2
  fi
  echo "" >&2
fi

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

# 5. Menu bar extra: an LSUIElement .app whose menu shows the project name, an
#    Enable/Disable hiding toggle and Quit. No Dock icon, no Cmd-Tab, no extra
#    permissions.
#
#    Deliberately NOT gated on HIDE_OK. Two reasons. A Homebrew cask already
#    moved the bundle into /Applications before this script ever ran, so there
#    is nothing here to install — only to leave alone. And when hiding does not
#    verify (Spotify >= 1.3.1 quits on LSUIElement=true), the icon is the one
#    control surface the user has left: `status` and `restore` both work, and
#    the toggle is how they get back to normal. Only HIDE_OK gating belongs on
#    the watcher, below, which has nothing to do without hiding.
if [ "${INSTALL_MENUBAR:-1}" = "0" ]; then
  echo "skipping menu bar app (INSTALL_MENUBAR=0)"
else
  MENUBAR_DEST="/Applications/headless-spotify.app"
  MENUBAR_APP=""
  # Candidate order: tarball root (release download), Homebrew prefix
  # (share/headless-spotify/../..), dist/ (local build), then build it.
  for candidate in \
    "$SCRIPT_DIR/headless-spotify.app" \
    "$SCRIPT_DIR/../headless-spotify.app" \
    "$SCRIPT_DIR/../../headless-spotify.app" \
    "$SCRIPT_DIR/dist/headless-spotify.app"; do
    if [ -d "$candidate" ]; then
      MENUBAR_APP="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      break
    fi
  done
  # A bundle already in /Applications was put there by `brew install --cask`,
  # which owns it. Building a second copy to overwrite it would defeat the
  # upgrade path, so leave it and just make sure it is running.
  if [ -z "$MENUBAR_APP" ] && [ ! -d "$MENUBAR_DEST" ] \
    && [ -f "$SCRIPT_DIR/scripts/build-menubar.sh" ]; then
    "$SCRIPT_DIR/scripts/build-menubar.sh" >/dev/null 2>&1 || true
    if [ -d "$SCRIPT_DIR/dist/headless-spotify.app" ]; then
      MENUBAR_APP="$SCRIPT_DIR/dist/headless-spotify.app"
    fi
  fi
  if [ -n "$MENUBAR_APP" ]; then
    pkill -f headless-spotify-bar 2>/dev/null || true
    rm -rf "$MENUBAR_DEST"
    cp -R "$MENUBAR_APP" "$MENUBAR_DEST"
    echo "installed menu bar app -> $MENUBAR_DEST"
  elif [ -d "$MENUBAR_DEST" ]; then
    echo "menu bar app already at $MENUBAR_DEST (installed by Homebrew) — leaving it"
  else
    echo "warning: menu bar app not built — run ./scripts/build-menubar.sh to get it" >&2
  fi
  if [ -d "$MENUBAR_DEST" ]; then
    if sudo -u "$SUDO_USER" /usr/bin/open -g "$MENUBAR_DEST" 2>/dev/null; then
      echo "menu bar app launched — click its icon in the top bar for the name + Quit menu"
    else
      echo "launch it any time with: open \"$MENUBAR_DEST\""
    fi
  fi
fi

# 6. Watcher LaunchAgent: generate from the CLI (single source of truth) and
#    bootstrap it as the console user so hiding survives updates + restarts.
#    Skipped when hiding failed: a daemon whose only job is to maintain hiding
#    has nothing to do, and would otherwise quit and relaunch a perfectly good
#    Spotify every few minutes. It stays one command away for later.
if [ "$HIDE_OK" -eq 0 ] && [ "${KEEP_ON_FAILURE:-0}" != "1" ]; then
  echo "skipping the watcher LaunchAgent (hiding did not verify) — start it later with:"
  echo "  headless-spotify watch --install-agent"
else
  USER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  if [ -n "$USER_HOME" ]; then
    AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
    sudo -u "$SUDO_USER" mkdir -p "$AGENTS_DIR"
    sudo -u "$SUDO_USER" "$BIN" watch --print-agent-plist --spotify-app "$SPOTIFY_APP" --interval 15 > "$AGENTS_DIR/com.headless-spotify.watcher.plist"
    chown "$SUDO_USER" "$AGENTS_DIR/com.headless-spotify.watcher.plist"
    chmod 0644 "$AGENTS_DIR/com.headless-spotify.watcher.plist"
    sudo -u "$SUDO_USER" /bin/launchctl bootout "gui/$(id -u "$SUDO_USER")" "$AGENTS_DIR/com.headless-spotify.watcher.plist" 2>/dev/null || true
    if sudo -u "$SUDO_USER" /bin/launchctl bootstrap "gui/$(id -u "$SUDO_USER")" "$AGENTS_DIR/com.headless-spotify.watcher.plist" 2>/dev/null; then
      echo "watcher agent loaded"
    else
      echo "warning: could not load the watcher agent — enable it later with:" >&2
      echo "  headless-spotify watch --install-agent" >&2
    fi
  fi
fi

if [ "$HIDE_OK" -eq 1 ]; then
  echo "done: Spotify is headless. Verify any time with: headless-spotify status"
else
  echo "done: CLI, dylib and menu bar app installed. Spotify is untouched and back to normal."
  echo "Verify any time with: headless-spotify status"
fi
