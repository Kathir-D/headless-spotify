# headless-spotify

[![CI](https://github.com/Kathir-D/headless-spotify/actions/workflows/ci.yml/badge.svg)](https://github.com/Kathir-D/headless-spotify/actions)
[![macOS](https://img.shields.io/badge/macOS-15%2B-lightgrey)](#requirements)
[![version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/Kathir-D/headless-spotify/releases)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Run official Spotify on macOS with **no Dock icon and no Cmd-Tab entry** — windows still work, AppleScript still works, so [Sonar](https://github.com/Kathir-D/sonar) controls it identically to normal Spotify. No Premium, no API key, no Soloist/librespot.

## Table of Contents

- [Features](#features)
- [Current status](#current-status)
- [Requirements](#requirements)
- [Install](#install)
- [Homebrew](#homebrew)
- [Usage](#usage)
- [Menu bar extra](#menu-bar-extra)
- [How it works](#how-it-works)
- [Sonar compatibility](#sonar-compatibility)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Developing](#developing)
- [Credits & provenance](#credits--provenance)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Hides Spotify from the Dock and Cmd-Tab**, keeps windows and playback working.
- **Keeps the Spotify contract intact**: process stays `com.spotify.client`, scripting dictionary untouched — Sonar matches by bundleID + `player state` only.
- **Two hiding methods with automatic fallback** (`hide --mode auto`, the default): `LSUIElement` plist mode first, accessory-policy injector second.
- **Watcher daemon** (LaunchAgent) re-applies hiding when Spotify self-updates or the Dock icon returns.
- **Media passthrough** (`control play|pause|toggle|next|previous|volume|…`) using the same AppleScript Sonar uses — never launches Spotify as a side effect.
- **Menu bar extra**: a top-bar icon whose menu shows the project name, an **Enable/Disable hiding** toggle that drives the same CLI, and Quit. It is itself `LSUIElement`, so it has no Dock icon and no Cmd-Tab entry.
- **Safe by design**: `install.sh` backs up `Info.plist` (+ the code-seal file); `restore`/`uninstall.sh` bring back the original Apple signature. `sudo` is needed only for install.
- **Zero dependencies**: Swift standard library + Foundation/AppKit only. No API keys, no certs, nothing to configure.

## Current status

> ⛔ **Blocked on Spotify ≥1.3.1 (verified 2026-09-28, macOS 26):** with
> `LSUIElement=true` present (ad-hoc seal, `codesign --verify` clean),
> Spotify 1.3.1.234 exits silently on launch — plain `open -a Spotify`
> fails too; removing the key restores launching. So on current Spotify the
> plist path cannot produce a running app, and `hide` exits 1 with a
> pointer to `restore`. If Spotify ever honors LSUIElement again, no code
> changes are needed — only this notice.

The injector fallback is likewise inert against current official Spotify: its
hardened runtime strips `DYLD_*` variables at exec, so the dylib is ignored
(plist mode stays primary). Everything is implemented and verified where
verifiable (test fixture flips prohibited→accessory, bundle-ID gate holds);
the CLI enforces the situation honestly — `hide` exits 1, `status` reports
not-headless, `restore` returns to normal.

## Requirements

- macOS 15+ (Sequoia or later).
- Official Spotify.app (Free tier works) at `/Applications/Spotify.app` (or pass `--spotify-app`).
- Xcode Command Line Tools (`swift`) — enough to build, install, and use.
- Full Xcode — only needed to run `swift test` (see [Developing](#developing)).

## Install

```sh
git clone https://github.com/Kathir-D/headless-spotify.git && cd headless-spotify
sudo ./install.sh /Applications/Spotify.app
```

What it does:

1. Builds the release CLI + dylib (or reuses a prebuilt `bin/`), installs them to `/usr/local/bin` and `/usr/local/lib/headless-spotify/`.
2. Backs up `Info.plist` (+ the code-seal file), sets `LSUIElement=true`, ad-hoc re-signs (credit: [4ian/hide-spotify-from-dock](https://github.com/4ian/hide-spotify-from-dock)).
3. Relaunches Spotify headless **as you** (`NSWorkspace.openApplication(activates:false)`) and polls `player state` for up to 10 s.
4. Installs and launches the menu bar extra at `/Applications/headless-spotify.app` (skip with `INSTALL_MENUBAR=0 sudo ./install.sh`).
5. Loads the watcher LaunchAgent so hiding survives updates + restarts.

`sudo` is needed only here (bundle edit + system paths) — the CLI itself never needs root.

If hiding does not verify — which is what happens on Spotify ≥1.3.1 today — `install.sh` **does not fail and does not leave Spotify broken**: it prints an explanation, rolls `Info.plist` back, relaunches Spotify normally, and continues installing the CLI, dylib, menu bar app, and watcher. Pass `KEEP_ON_FAILURE=1` if you'd rather keep `LSUIElement` set anyway.

> **Gatekeeper:** the release artifacts are ad-hoc signed, not notarized. A tarball downloaded in a browser is quarantined, so macOS may refuse to run it. Use Homebrew (no quarantine), or clear it once:
> `xattr -dr com.apple.quarantine <folder>` — or right-click the app → Open → Open.

## Homebrew

The formula lives in this repo at [`Formula/headless-spotify.rb`](Formula/headless-spotify.rb) and installs the CLI, the injector dylib, and the menu bar app into `/Applications`. Its `url` + `sha256` point at the GitHub release tarball and are refreshed automatically by the [release workflow](.github/workflows/release.yml) on every `v*` tag, so they are only correct after a release exists.

To publish, mirror the formula into a tap of your own (`homebrew-<name>/homebrew-<tap>`) and:

```sh
brew tap Kathir-D/<your-tap>
brew install headless-spotify
brew test headless-spotify
brew audit --strict --online Kathir-D/<your-tap>/headless-spotify
```

## Usage

```sh
headless-spotify status            # Dock? LSUIElement? player state? (exit 0 only when headless+scriptable)
headless-spotify status --json     # machine-readable, for Sonar/scripts
headless-spotify hide              # auto: plist → injector fallback
headless-spotify hide --mode plist # plist only
headless-spotify hide --mode injector --injector /path/to/libHeadlessSpotifyInjector.dylib
headless-spotify hide --dry-run    # print the plan, change nothing
headless-spotify restore           # original plist (+ Apple signature) back, relaunch normally
headless-spotify watch --interval 15            # persistence daemon
headless-spotify watch --install-agent          # install + load LaunchAgent now
headless-spotify watch --print-agent-plist      # show the agent definition

# Media passthrough (same AppleScript Sonar uses; never launches Spotify)
headless-spotify control play | pause | toggle | next | previous
headless-spotify control volume                 # print 0–100
headless-spotify control set-volume 70          # note: Spotify ≥1.3.x ignores sets
```

Example session (headless state):

```sh
$ headless-spotify status
Spotify: /Applications/Spotify.app (com.spotify.client)
Installed: yes
LSUIElement: true (headless)
Dock: hidden (accessory)
Player state: paused
Backup: present
Headless: yes — scriptable: yes
```

Verify against either mode (normal or headless) with the same contract Sonar uses:

```applescript
tell application "Spotify" to get player state
--> playing / paused / stopped
```

Match by `bundleID == com.spotify.client`, never by Dock or window presence.

## Menu bar extra

`install.sh` also drops a small menu bar app in `/Applications/headless-spotify.app`. It adds a waveform icon to the top bar; clicking it opens a menu with the project name (greyed out), an **Enable/Disable hiding** toggle, and **Quit headless-spotify**.

```
headless-spotify 0.1.0        (greyed out)
──────────────────────────
Disable hiding               ← or "Enable hiding"
──────────────────────────
Quit headless-spotify
```

- The toggle label follows the real state and is recomputed every time you open the menu, so it never lies — even if you change things from the terminal or the watcher does.
- It drives the `headless-spotify` binary (`hide` / `restore`) rather than reimplementing it, so the menu and the CLI can never disagree. If the binary isn't found (e.g. you copied only the `.app`), the row reads `headless-spotify CLI not found`.
- On the usual root-owned `/Applications/Spotify.app`, enabling asks for your password once: the plist edit + re-sign runs as root, the relaunch still runs as you, so Spotify keeps your session. Hiding takes a while (deep re-sign + a scripting wait), so the row shows `Working…` and cannot be double-clicked.
- If a toggle fails, its first line of output appears as a greyed row until you reopen the menu.

```sh
open /Applications/headless-spotify.app     # start it
pkill -f headless-spotify-bar               # or stop it from the CLI
headless-spotify-bar --print-menu-spec      # show the menu without a GUI
headless-spotify-bar --print-menu-spec --hiding-enabled   # pin the state (for tests)
```

It is packaged as an `LSUIElement` app, so it has no Dock icon and no Cmd-Tab entry — the same trick applied to Spotify — and it needs no Accessibility or Automation permission. Everything else stays on the CLI on purpose: a status bar app that duplicated every subcommand would drift from the real behaviour.

Build it yourself (a release tarball already ships the `.app` ready to copy):

```sh
./scripts/build-menubar.sh   # → dist/headless-spotify.app
```

## How it works

Two hiding methods, tried in order (`hide --mode auto`, the default):

1. **LSUIElement mode (primary).** Sets `LSUIElement=true` in
   `/Applications/Spotify.app/Contents/Info.plist`, ad-hoc re-signs (Apple
   Silicon refuses to relaunch an edited bundle otherwise), then relaunches
   Spotify headless and polls `player state` for up to 10 s. Concept credit:
   [4ian/hide-spotify-from-dock](https://github.com/4ian/hide-spotify-from-dock) (MIT).
2. **Injector fallback.** If the Dock icon survives plist mode, Spotify is
   relaunched with `DYLD_INSERT_LIBRARIES` pointing at
   `libHeadlessSpotifyInjector.dylib`, whose constructor forces
   `setActivationPolicy: → Accessory`. Concept credit:
   [michaelmitchell-bit/hide-macos-app-dock-icon](https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon) (MIT).
   The dylib is bundle-ID gated to `com.spotify.client`, so it can never
   alter your other apps. See [Current status](#current-status) for why it is
   inert against today's hardened Spotify build.

A **watcher daemon** (`headless-spotify watch`, kept alive by a LaunchAgent)
re-applies hiding when Spotify self-updates (updates wipe `Info.plist`) or the
Dock icon returns: stale launch → relaunch headless; wiped plist → redo
plist + re-sign + relaunch; Dock survives plist mode → injector. If hiding keeps
failing (the Spotify ≥1.3.1 case above), the watcher backs off exponentially —
2×, 4×, 8×, then every 16 intervals — so it never spins on quit + re-sign.

## Sonar compatibility

| Spotify mode | Sonar sees it | Control |
|---|---|---|
| Normal | yes | play/pause/volume/track |
| Headless (`LSUIElement`) | yes — **blocked on Spotify ≥1.3.1**, see above | same (when Spotify honors the key) |
| Headless (injector) | yes — **blocked by hardened runtime**, see above | same (when injection applies) |

Both headless modes keep the same bundle ID and scripting dictionary, so
Sonar needs no changes between rows. Today, only the Normal row runs on
Spotify 1.3.1; the CLI enforces this honestly (`hide` exits 1, `status`
reports not-headless, `restore` returns to normal).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `hide` exits 1, Spotify won't stay launched headless | Spotify ≥1.3.1 quits when `LSUIElement=true` is present | Run `headless-spotify restore`; track Spotify releases — no code change needed if they honor the key again |
| Dock icon back after Spotify update | Updates rewrite `Info.plist` | Watcher re-applies automatically; or re-run `headless-spotify hide` |
| `hide` says bundle not writable | Root-owned `/Applications` copy | Run `sudo ./install.sh` (the one sudo step) |
| Spotify won't launch after `hide` | Edited bundle, re-sign failed | Re-run `hide` (look for the re-sign error), or `restore` + reinstall Spotify |
| `restore` warns signature invalid | Seal files diverge (e.g. manual edits after backup) | Reinstall Spotify from spotify.com, then `hide` again |
| First `status`/`hide` prompts for automation access | macOS asks once before `osascript` may control Spotify | Allow it; afterwards everything is non-interactive |
| Injector seemingly does nothing | Hardened Spotify strips `DYLD_*` | Expected — plist mode is primary; see [Current status](#current-status) |
| `control set-volume` reports the old volume | Spotify ≥1.3.x ignores AppleScript volume sets (verified live 2026-09-28) | Use media keys / the volume slider; Sonar's volume control hits the same Spotify-side wall — `play/pause/next/previous` all work |
| Watcher log | `/tmp/headless-spotify-watcher.log` | `headless-spotify status` tells current state |

Permissions note: no Accessibility permission is needed. The only prompt is
the one-time AppleEvents authorization for controlling Spotify, which Sonar
users have already granted.

## Uninstall

```sh
./uninstall.sh /Applications/Spotify.app   # sudo only if the bundle is root-owned
```

Restores the original `Info.plist` + seal (Apple's signature verifies again),
relaunches Spotify normally, unloads/removes the agent, quits and removes the
menu bar app, removes the CLI + dylib. Your Dock icon comes back; nothing else
changes.

## Developing

```sh
swift build          # CLI + injector dylib + menu bar extra (Command Line Tools are enough)
swift test           # 65 tests in 16 suites, all offline-safe (fixtures, stubbed runners)
./scripts/smoke-test.sh            # pre-release gate (pass --live to exercise real media controls)
./scripts/build-menubar.sh          # menu bar app bundle (debug: CONFIG=debug)
./scripts/package-release.sh       # versioned tarball + SHA256SUMS.txt (see VERSION)
```

`swift test` needs full Xcode (the Command Line Tools ship no test framework). With Xcode installed but not selected, run it via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

Layout: `Sources/HeadlessSpotify/*` (CLI), `Sources/HeadlessSpotifyBar/*` +
`Sources/HeadlessSpotifyBarKit/*` (menu bar extra), `Sources/CHeadlessInjector/*`
(dylib), `Tests/HeadlessSpotifyTests/*`, `install.sh` / `uninstall.sh`,
`launchagent/*.plist`, `Formula/headless-spotify.rb`,
`scripts/package-release.sh` + `scripts/smoke-test.sh`.

## Credits & provenance

| What | Source | Author | License | How used |
|---|---|---|---|---|
| `LSUIElement` trick | https://github.com/4ian/hide-spotify-from-dock | @4ian | MIT 2016 | Backup + set + restore, with attribution |
| Injector fallback concept | https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon | @michaelmitchell-bit | MIT | Re-implemented as bundle-ID-gated dylib, with attribution |
| Soloist / librespot | — | — | — | **Not used** (Linux-only / Premium-only) |

Full texts: see `THIRD-PARTY-NOTICES.md` + `LICENSE`.

## Contributing

Issues and small PRs welcome. Conventional commits (`feat:`, `fix:`, `docs:`,
`test:`, `chore:`), `git status` before committing. Before opening a PR,
run `swift build`, `swift test` (full Xcode), and `./scripts/smoke-test.sh`.

## License

MIT — see `LICENSE`.
