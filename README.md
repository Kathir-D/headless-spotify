# headless-spotify

[![CI](https://github.com/Kathir-D/headless-spotify/actions/workflows/ci.yml/badge.svg)](https://github.com/Kathir-D/headless-spotify/actions)
[![macOS](https://img.shields.io/badge/macOS-15%2B-lightgrey)](#requirements)
[![version](https://img.shields.io/github/v/release/Kathir-D/headless-spotify?label=version)](https://github.com/Kathir-D/headless-spotify/releases)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Run official Spotify on macOS with **no Dock icon and no Cmd-Tab entry** — windows still work, AppleScript still works, so [Sonar](https://github.com/Kathir-D/sonar) controls it identically to normal Spotify. No Premium, no API key, no Soloist/librespot.

## Contents

- [Features](#features)
- [Current status](#current-status)
- [Requirements](#requirements)
- [Install](#install)
  - [Homebrew (recommended)](#homebrew-recommended)
  - [Direct download](#direct-download)
  - [Build from source](#build-from-source)
  - [What install.sh does](#what-installsh-does)
- [Usage](#usage)
- [Menu bar extra](#menu-bar-extra)
- [How it works](#how-it-works)
- [What it will not do to your Spotify](#what-it-will-not-do-to-your-spotify)
- [Sonar compatibility](#sonar-compatibility)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Developing](#developing)
- [Contributing](#contributing)
- [Publishing to Homebrew](#publishing-to-homebrew)
- [Credits & provenance](#credits--provenance)
- [License](#license)

## Features

[⬆ Back to top](#headless-spotify)

- **Hides Spotify from the Dock and Cmd-Tab**, keeps windows and playback working.
- **Keeps the Spotify contract intact**: process stays `com.spotify.client`, scripting dictionary untouched — Sonar matches by bundleID + `player state` only.
- **Two hiding methods with automatic fallback** (`hide --mode auto`, the default): `LSUIElement` plist mode first, accessory-policy injector second.
- **Watcher daemon** (LaunchAgent) re-applies hiding when Spotify self-updates or the Dock icon returns.
- **Media passthrough** (`control play|pause|toggle|next|previous|volume|…`) using the same AppleScript Sonar uses — never launches Spotify as a side effect.
- **Menu bar extra**: a top-bar icon whose menu shows the project name, an **Enable/Disable hiding** toggle that drives the same CLI, and Quit. It is itself `LSUIElement`, so it has no Dock icon and no Cmd-Tab entry.
- **Safe by design**: `install.sh` backs up `Info.plist` (+ the code-seal file); `restore`/`uninstall.sh` bring back the original Apple signature. `sudo` is needed only for install.
- **Zero dependencies**: Swift standard library + Foundation/AppKit only. No API keys, no certs, nothing to configure.

## Current status

[⬆ Back to top](#headless-spotify)

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

[⬆ Back to top](#headless-spotify)

- macOS 15+ (Sequoia or later).
- Official Spotify.app (Free tier works) at `/Applications/Spotify.app` (or pass `--spotify-app`).
- Xcode Command Line Tools (`swift`) — enough to build, install, and use.
- Full Xcode — only needed to run `swift test` (see [Developing](#developing)).

## Install

### Homebrew (recommended)

```sh
brew tap Kathir-D/tap
brew trust --tap Kathir-D/tap
brew install kathir-d/tap/headless-spotify
sudo "$(brew --prefix headless-spotify)/install.sh"
```

`Kathir-D/tap` is the same tap that ships [Sonar](https://github.com/Kathir-D/Sonar). `brew trust` is
required: Homebrew 7 refuses to load formulae from an untrusted tap, and without it you get
`Refusing to load formula … from untrusted tap`. The first `brew install` only puts the
files in place — nothing touches Spotify. The second command is the part that edits Spotify, so it
is kept separate and explicit.

### Direct download

```sh
curl -fLO https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0-beta.2/headless-spotify-0.1.0-beta.2-macos.tar.gz
curl -fLO https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0-beta.2/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
tar -xzf headless-spotify-0.1.0-beta.2-macos.tar.gz
cd headless-spotify-0.1.0-beta.2
sudo ./install.sh /Applications/Spotify.app
```

`curl` does not set the quarantine attribute, so this may not prompt at all. A **browser** download
always does — if macOS refuses to run the app or the CLI, run
`xattr -dr com.apple.quarantine .` in the extracted folder, or approve once in
**System Settings › Privacy & Security › Open Anyway**. The artifacts are ad-hoc signed, not
notarized, because the project has no paid Apple Developer account.

### Build from source

```sh
git clone https://github.com/Kathir-D/headless-spotify.git
cd headless-spotify
swift build            # Command Line Tools are enough for this
sudo ./install.sh /Applications/Spotify.app
```

`install.sh` reuses `swift build -c release` products when it finds them, so a plain `swift build`
is enough; it only builds for itself if there is nothing to reuse. `swift test` additionally needs
full Xcode — with Xcode installed but not selected, run
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

### What install.sh does

| Step | What it does | Needs `sudo` |
| --- | --- | --- |
| 1 | Installs the CLI to `/usr/local/bin` and the injector dylib to `/usr/local/lib/headless-spotify/` | yes |
| 2 | Backs up `Info.plist` **and** its code seal, sets `LSUIElement=true`, ad-hoc re-signs | yes |
| 3 | Relaunches Spotify headless **as you** (`activates:false`) and polls `player state` for up to 10 s | no |
| 4 | Installs and launches the menu bar app at `/Applications/headless-spotify.app` | yes |
| 5 | Loads the watcher LaunchAgent so hiding survives Spotify updates and restarts | partly |

`sudo` is needed only for this one command — the CLI itself never needs root.

| Flag | Effect |
| --- | --- |
| `INSTALL_MENUBAR=0` | Skip the menu bar app (CLI + watcher only) |
| `KEEP_ON_FAILURE=1` | If hiding fails, keep `LSUIElement` set instead of rolling back |

> **If hiding does not verify — which is what happens on Spotify ≥1.3.1 today — `install.sh` does
> not fail and does not leave Spotify broken.** It prints an explanation, rolls `Info.plist` back,
> relaunches Spotify normally, and finishes installing the CLI, dylib and menu bar app. It then
> **skips the watcher**, because a daemon whose only job is to maintain hiding has nothing to do
> and would otherwise quit and relaunch a healthy Spotify every few minutes. Start it whenever
> hiding actually works: `headless-spotify watch --install-agent`.

[⬆ Back to top](#headless-spotify)

## Usage

[⬆ Back to top](#headless-spotify)

```sh
headless-spotify status            # Dock? LSUIElement? player state? (exit 0 only when headless+scriptable)
headless-spotify status --json     # machine-readable, for Sonar/scripts
headless-spotify hide              # auto: plist → injector fallback
headless-spotify hide --mode plist # plist only
headless-spotify hide --mode injector --injector /path/to/libHeadlessSpotifyInjector.dylib
headless-spotify hide --dry-run    # print the plan, change nothing
headless-spotify restore           # original plist (+ Apple signature) back, relaunch normally
                                  # if there is nothing to restore it leaves Spotify running
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

[⬆ Back to top](#headless-spotify)

`install.sh` also drops a small menu bar app in `/Applications/headless-spotify.app`. It adds a waveform icon to the top bar; clicking it opens a menu with the project name (greyed out), an **Enable/Disable hiding** toggle, and **Quit headless-spotify**.

```
headless-spotify 0.1.0        (greyed out)
──────────────────────────
✓ Hidden from Dock            ← ticked while Spotify is out of the Dock
──────────────────────────
Quit headless-spotify
```

The row is a **state**, not an action: it is ticked exactly when Spotify is hidden, and clicking it
flips that. The menu bar icon follows the same state — a crossed-out eye while hidden, a music
note while Spotify shows in the Dock — so you never have to open the menu to know, and never have
to quit anything.

- The tick and the icon follow the real state and are recomputed every time the menu opens, so they never lie — even if you change things from the terminal or the watcher does.
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

[⬆ Back to top](#headless-spotify)

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

## What it will not do to your Spotify

This project edits a signed system bundle, so the rules it holds itself to are stricter than
"it usually works". Every one of these is enforced in code, not left to judgement:

| | Guarantee |
| --- | --- |
| **A failed hide is rolled back** | If hiding does not verify, `install.sh` restores `Info.plist` and relaunches Spotify. It never leaves you with a Spotify that will not start, and it never exits "successfully" while Spotify is broken |
| **A version that cannot be hidden is left alone** | After 3 failed attempts the watcher marks that Spotify version unhideable and stops touching it completely — no more quitting, no more re-signing. It only retries when Spotify's version actually changes |
| **It never fights you** | `restore` is always available, works while hidden, and needs no arguments. If there is nothing to restore it changes nothing and leaves Spotify running, so running it out of caution cannot interrupt playback |
| **A stale backup is never applied** | If Spotify auto-updated while hidden, `restore` removes only the key we added instead of copying an old `Info.plist` over the new one. The original Apple signature cannot be recovered from a stale backup, and it says so |
| **Uninstall stops everything first** | The watcher and the menu bar app are killed *before* the bundle is restored, so a running daemon cannot re-hide Spotify mid-uninstall |
| **Your data and settings are never touched** | Only `LSUIElement` is written, and only the two files that are backed up first: `Contents/Info.plist` and `Contents/_CodeSignature/CodeResources` |
| **The injector cannot reach other apps** | `libHeadlessSpotifyInjector.dylib` is gated on `bundleID == com.spotify.client` and does nothing in any other process |
| **It only ever edits Spotify** | `hide` refuses any bundle whose identifier is not `com.spotify.client`, so a wrong `--spotify-app` cannot de-icon some other app. `--force` overrides it deliberately |
| **The CLI never needs root** | `sudo` appears once, in `install.sh`. Every other command runs as you |
| **Playback restarts, nothing else** | Hiding must relaunch Spotify, so playback restarts. No playlist, library or account state is altered |
| **One-time kill switch** | `headless-spotify watch --uninstall-agent` stops the watcher without uninstalling anything |

[⬆ Back to top](#headless-spotify)

## Sonar compatibility

[⬆ Back to top](#headless-spotify)

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

[⬆ Back to top](#headless-spotify)

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

[⬆ Back to top](#headless-spotify)

```sh
./uninstall.sh /Applications/Spotify.app   # sudo only if the bundle is root-owned
```

Restores the original `Info.plist` + seal (Apple's signature verifies again),
relaunches Spotify normally, unloads/removes the agent, quits and removes the
menu bar app, removes the CLI + dylib. Your Dock icon comes back; nothing else
changes.

## Developing

[⬆ Back to top](#headless-spotify)

```sh
swift build          # CLI + injector dylib + menu bar extra (Command Line Tools are enough)
swift test           # 87 tests in 23 suites, all offline-safe (fixtures, stubbed runners)
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

## Contributing

[⬆ Back to top](#headless-spotify)

Issues and small PRs welcome. Conventional commits (`feat:`, `fix:`, `docs:`,
`test:`, `chore:`), `git status` before committing. Before opening a PR,
run `swift build`, `swift test` (full Xcode), and `./scripts/smoke-test.sh`.

## Publishing to Homebrew

The formula lives in this repo at [`Formula/headless-spotify.rb`](Formula/headless-spotify.rb). Its
`url` and `sha256` point at the GitHub release tarball and are rewritten automatically by
[`.github/workflows/release.yml`](.github/workflows/release.yml) on every `v*` tag — never hand-edit
them, or CI will overwrite your change on the next release.

The same run copies the formula into the tap,
[`Kathir-D/homebrew-tap`](https://github.com/Kathir-D/homebrew-tap), which is what `brew install`
reads. It pushes with `TAP_DEPLOY_KEY`, a repository secret holding a deploy key that can write to
that tap and nothing else. If the step fails, the release is already up: fix the secret and re-run
the job. Verify a release with:

```sh
brew update
brew upgrade kathir-d/tap/headless-spotify   # or `brew install` the first time
brew test kathir-d/tap/headless-spotify
brew audit --strict --online kathir-d/tap/headless-spotify
```

`brew test` checks the CLI version, the usage error for a missing bundle, and that the menu bar app
landed in `/Applications` with `LSUIElement` set. CI runs `brew audit --strict` on every push, so a
formula that would be rejected upstream is caught before it is tagged.

> **Why a personal tap rather than `homebrew/core`?** Homebrew's policy requires anything in its
> official repositories to be assessable by Gatekeeper, and a formula must not need `sudo` to become
> useful. headless-spotify is ad-hoc signed and un-notarized, and hiding Spotify necessarily edits a
> root-owned system bundle — so it belongs in your own tap, which is exactly what
> [`Kathir-D/Sonar`](https://github.com/Kathir-D/Sonar) does for the same reason.

[⬆ Back to top](#headless-spotify)

## Credits & provenance

[⬆ Back to top](#headless-spotify)

| What | Source | Author | License | How used |
|---|---|---|---|---|
| `LSUIElement` trick | https://github.com/4ian/hide-spotify-from-dock | @4ian | MIT 2016 | Backup + set + restore, with attribution |
| Injector fallback concept | https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon | @michaelmitchell-bit | MIT | Re-implemented as bundle-ID-gated dylib, with attribution |
| Soloist / librespot | — | — | — | **Not used** (Linux-only / Premium-only) |

Full texts: see `THIRD-PARTY-NOTICES.md` + `LICENSE`.

## License

[⬆ Back to top](#headless-spotify)

MIT — see `LICENSE`.
