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
    - [Permissions](#permissions)
    - [If Spotify is still in the Dock](#if-spotify-is-still-in-the-dock)
  - [Direct download](#direct-download)
  - [Build from source](#build-from-source)
  - [What install.sh does](#what-installsh-does)
- [Usage](#usage)
- [Menu bar extra](#menu-bar-extra)
- [How it works](#how-it-works)
- [What it will not do to your Spotify](#what-it-will-not-do-to-your-spotify)
- [Companions](#companions)
  - [Sonar](#sonar)
  - [Works with trak](#works-with-trak)
  - [`status --json` contract](#status---json-contract)
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
- **Background launch** (`launch`): starts Spotify without activating it and waits for `player state`; a no-op if Spotify is already running. Never edits `Info.plist`, never needs `sudo`.
- **Media passthrough** (`control play|pause|toggle|next|previous|volume|…`) using the same AppleScript Sonar uses — never launches Spotify as a side effect.
- **Menu bar extra**: a top-bar icon whose menu shows the project name, an **Enable/Disable hiding** toggle that drives the same CLI, and Quit. It is itself `LSUIElement`, so it has no Dock icon and no Cmd-Tab entry. `brew install --cask` puts it in `/Applications` and starts it — no `sudo`, and it does not wait for hiding to work.
- **An app icon in Sonar's colourway**: a macOS squircle with a disc ramped 45° from `#5BCEFA` to `#F5A9B8` and a white music note in the middle — the same mark the top bar shows. It is drawn by `scripts/make-icon.swift` on every build rather than checked in as a bitmap, so the colours are a one-line edit.
- **Safe by design**: `install.sh` backs up `Info.plist` (+ the code-seal file); `restore`/`uninstall.sh` bring back the original Apple signature. `sudo` is needed only to edit Spotify's bundle.
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

**What this does *not* block.** Installing, the menu bar extra, `status` and
`restore` are all unaffected, and none of them are gated on hiding working. That
is deliberate: on a Spotify that cannot be hidden, the top-bar icon is the only
control surface left, so `install.sh` installs and launches it either way and
only skips the watcher (whose entire job is maintaining hiding, and which would
otherwise quit and relaunch a perfectly good Spotify every few minutes).

## Requirements

[⬆ Back to top](#headless-spotify)

- macOS 15+ (Sequoia or later).
- Official Spotify.app (Free tier works) at `/Applications/Spotify.app` (or pass `--spotify-app`).
- Xcode Command Line Tools (`swift`) — enough to build, install, and use.
- Full Xcode — only needed to run `swift test` (see [Developing](#developing)).

## Install

### Homebrew (recommended)

```sh
brew install --cask kathir-d/tap/headless-spotify
```

One command. No `sudo` to type, no `brew tap` preamble, no `brew trust`, and
nothing else to run afterwards. It leaves three things behind:

| What | Where |
| --- | --- |
| **The menu bar extra**, already running — look for the music note in the top bar | `/Applications/headless-spotify.app` |
| The `headless-spotify` CLI | `$(brew --prefix)/bin` |
| The privileged install helper, bundled with the app | `/Applications/headless-spotify.app/Contents/Resources/install.sh` |

### Permissions

The app asks for them, rather than leaving you to find out you needed them.

Everything here drives Spotify through AppleScript, and macOS only ever prompts
when something actually asks. So the app asks on launch: if it is not yet
allowed to control Spotify, **Allow control of Spotify** appears in its menu and
clicking it raises the system dialog. There is no `sudo` command to copy out of
a README, and no failure to diagnose after the fact.

A refused permission cannot be re-asked — macOS will not prompt twice — so the
row then says so and points at System Settings, and clicking it is disabled
rather than silently doing nothing.

`Kathir-D/tap` is the same tap that ships [Sonar](https://github.com/Kathir-D/Sonar)
and [Stockroom](https://github.com/Kathir-D/Stockroom). There is deliberately no
`brew tap` or `brew trust` line: a fully qualified `user/tap/name` makes
Homebrew tap the repository and trust the cask before resolving it, so
`brew update` and `brew upgrade --cask` work straight afterwards. Add
`brew trust --tap Kathir-D/tap` only if you want short names like
`brew install --cask sonar`, which identify nothing.

### If Spotify is still in the Dock

Nothing is broken, and nothing is half-done. Hiding works by setting
`LSUIElement` in Spotify's `Info.plist` and re-signing the bundle, and **Spotify
1.3.1 and newer quit on launch whenever that key is present** — so the edit
provably cannot work there. The cask reads Spotify's version and *skips* the
edit rather than applying it and then half-undoing it, because a bundle cannot be
given back Spotify's Developer ID signature by anything on this machine.

`headless-spotify status` reports the same thing without prose:

```
LSUIElement: absent (normal)
Dock: visible (regular)
Headless: no — scriptable: yes
```

Everything else works now and will keep working: the menu bar toggle, `status`,
`restore`, `control`, and the watcher. If a future Spotify honours the key again,
no code change is needed — only this note.

> ⛔ **Read this before you run the `sudo` command, if you are on Spotify ≥1.3.1**
> (verified 2026-09-28, macOS 26 — that is the current version). Spotify quits
> on launch whenever `LSUIElement` is present in its `Info.plist`, so **hiding
> will not take effect**. The command still finishes cleanly: it installs the
> injector dylib, leaves the menu bar app in place and running, reports that
> hiding did not verify, rolls your `Info.plist` back, relaunches Spotify
> normally, and skips the watcher daemon. Nothing is left broken. The menu bar
> icon, `headless-spotify status` and `headless-spotify restore` all keep
> working — which is why the menu bar app is not gated on hiding at all: it is
> your status and control surface, and on a Spotify that cannot be hidden it is
> the only one you have. If Spotify ever honors `LSUIElement` again, no code
> change is needed — only this notice goes away.

**Coming from the old formula?** Releases up to `0.1.0-beta.2` shipped a
Homebrew *formula* called `headless-spotify`, which could not put a bundle in
`/Applications` — the `app` DSL is cask-only — so the app sat in the Cellar and
`brew install` looked like it had done nothing. Replace it with:

```sh
brew uninstall kathir-d/tap/headless-spotify        # the formula, if you have it
brew install --cask kathir-d/tap/headless-spotify   # the cask
```

If you already ran the old `install.sh`, nothing breaks: the cask's bundle
carries its own copy, and `sudo …/Contents/Resources/uninstall.sh` still undoes
the Spotify edit.

### Direct download

```sh
curl -fLO https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0-beta.4/headless-spotify-0.1.0-beta.4-macos.tar.gz
curl -fLO https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0-beta.4/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
tar -xzf headless-spotify-0.1.0-beta.4-macos.tar.gz
cd headless-spotify-0.1.0-beta.4
sudo ./install.sh /Applications/Spotify.app
```

There is no cask here, so `install.sh` does everything: it installs the CLI,
installs **and launches the menu bar app** in `/Applications`, then does the
privileged Spotify edit. `curl` does not set the quarantine attribute, so this
may not prompt at all. A **browser** download always does — if macOS refuses to
run the app or the CLI, run `xattr -dr com.apple.quarantine .` in the extracted
folder, or approve once in **System Settings › Privacy & Security › Open
Anyway**. The artifacts are ad-hoc signed, not notarized, because the project
has no paid Apple Developer account.

### Build from source

```sh
git clone https://github.com/Kathir-D/headless-spotify.git
cd headless-spotify
swift build            # Command Line Tools are enough for this
sudo ./install.sh /Applications/Spotify.app
```

`install.sh` reuses `swift build -c release` products when it finds them, so a
plain `swift build` is enough; it only builds for itself if there is nothing to
reuse. `swift test` additionally needs full Xcode — with Xcode installed but not
selected, run
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

### What install.sh does

The step numbers match `install.sh`'s own header.

| Step | What it does | Needs `sudo` | Done by the cask |
| --- | --- | --- | --- |
| 1 | Installs the CLI to `/usr/local/bin` | yes | yes — the cask links it into `$(brew --prefix)/bin` |
| 2 | Backs up `Info.plist` **and** its code seal, sets `LSUIElement=true`, ad-hoc re-signs | yes | **no — this is the privileged step** |
| 3 | Relaunches Spotify headless **as you** (`activates:false`) and polls `player state` for up to 10 s | no | no |
| 4 | Installs the injector dylib to `/usr/local/lib/headless-spotify/` | yes | yes — it ships in the app bundle |
| 5 | Installs and launches the menu bar app at `/Applications/headless-spotify.app` | yes | yes — `app "headless-spotify.app"` |
| 6 | Loads the watcher LaunchAgent so hiding survives Spotify updates and restarts | partly | no |

So under Homebrew what `install.sh` actually adds is steps 2, 3 and 6, and
step 2 is the only one that requires root. From a tarball or a checkout it does
all six.

`sudo` is needed only for this one command — the CLI itself never needs root.

| Flag | Effect |
| --- | --- |
| `INSTALL_MENUBAR=0` | Skip the menu bar app (CLI + watcher only) |
| `KEEP_ON_FAILURE=1` | If hiding fails, keep `LSUIElement` set instead of rolling back |

Two behaviours are worth stating outright, because both used to surprise people:

- **The menu bar app is not gated on hiding working.** Only the watcher is. When
  hiding does not verify, the app is still installed and launched, because its
  menu (`status`, the Enable/Disable toggle, `restore`) is the control surface
  you have left. If the app is already in `/Applications` — which is what the
  cask does — `install.sh` leaves it alone instead of overwriting the copy
  `brew upgrade` owns.
- **`install.sh` does not install a second copy of the CLI** when a
  `headless-spotify` is already on `PATH`. On Intel, Homebrew's prefix *is*
  `/usr/local`, so copying over it would break `brew upgrade` and leave a file
  `brew uninstall` does not know about.

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
headless-spotify status --json     # machine-readable, versioned ("schema": 1), for Sonar/trak/scripts
headless-spotify launch            # start Spotify in the background, wait ≤10 s for `player state`
                                  # no-op if already running; never edits Info.plist, no sudo
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

`brew install --cask` puts a small menu bar app in `/Applications/headless-spotify.app` and
starts it; from a tarball or a checkout, `install.sh` does the same. It adds a waveform icon to
the top bar; clicking it opens a menu with the project name (greyed out), an **Enable/Disable
hiding** toggle, and **Quit headless-spotify**.

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
- It drives the `headless-spotify` binary (`hide` / `restore`) rather than reimplementing it, so the menu and the CLI can never disagree. If the binary isn't found, the row reads `headless-spotify CLI not found`. The cask links it into `$(brew --prefix)/bin`, which is on `PATH`, so it is found.
- On the usual root-owned `/Applications/Spotify.app`, enabling asks for your password once: the plist edit + re-sign runs as root, the relaunch still runs as you, so Spotify keeps your session. Hiding takes a while (deep re-sign + a scripting wait), so the row shows `Working…` and cannot be double-clicked.
- If a toggle fails, its first line of output appears as a greyed row until you reopen the menu.

```sh
open /Applications/headless-spotify.app     # start it
pkill -f headless-spotify-bar               # or stop it from the CLI
headless-spotify-bar --print-menu-spec      # show the menu without a GUI
headless-spotify-bar --print-menu-spec --hiding-enabled   # pin the state (for tests)
```

It is packaged as an `LSUIElement` app, so it has no Dock icon and no Cmd-Tab entry — the same trick applied to Spotify. It needs no Accessibility permission, and it asks for the one Apple Events permission it does need rather than assuming it: see [Permissions](#permissions). Everything else stays on the CLI on purpose: a status bar app that duplicated every subcommand would drift from the real behaviour.

The bundle also carries `install.sh`, `uninstall.sh`, the injector dylib and the watcher
LaunchAgent definition in `Contents/Resources`, so the one privileged command is always
somewhere findable at a path that does not change between versions:

```sh
sudo /Applications/headless-spotify.app/Contents/Resources/install.sh
```

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

## Companions

[⬆ Back to top](#headless-spotify)

headless-spotify never changes Spotify's bundle ID or scripting dictionary,
so anything that drives Spotify over AppleScript keeps working. Two companion
tools are known to work with it:

| Tool | What it is | What it uses from headless-spotify |
|---|---|---|
| [Sonar](https://github.com/Kathir-D/sonar) | Spotify controller | Nothing — it matches `com.spotify.client` + `player state`, same as normal Spotify |
| [trak](https://github.com/Kathir-D/trak) | Terminal UI for Spotify | `status --json` for its "headless" badge; `launch` to start Spotify without stealing focus |

### Sonar

| Spotify mode | Sonar sees it | Control |
|---|---|---|
| Normal | yes | play/pause/volume/track |
| Headless (`LSUIElement`) | yes — **blocked on Spotify ≥1.3.1**, see above | same (when Spotify honors the key) |
| Headless (injector) | yes — **blocked by hardened runtime**, see above | same (when injection applies) |

Both headless modes keep the same bundle ID and scripting dictionary, so
Sonar needs no changes between rows. Today, only the Normal row runs on
Spotify 1.3.1; the CLI enforces this honestly (`hide` exits 1, `status`
reports not-headless, `restore` returns to normal).

### Works with trak

[trak](https://github.com/Kathir-D/trak) is a terminal UI for Spotify. It
talks to Spotify over AppleScript, so it works the same whether Spotify is
normal or headless. When headless-spotify is installed, trak can use two
commands:

- **`headless-spotify status --json`** — trak reads `headless` to show a
  "headless" badge. Any `schema` other than `1` should be treated as
  unknown (see the contract below).
- **`headless-spotify launch`** — starts Spotify in the background
  (`activates:false`, so no focus steal and no Dock bounce) and waits up to
  `--timeout` (default 10 s) for `player state`. Exit codes:

  | Exit | Meaning |
  |---|---|
  | 0 | Spotify is running and answered `player state`, or was already running (then nothing is done) |
  | 1 | Spotify is missing, could not be started, or did not answer in time (the reason is on stderr) |

  `launch` is safe to call from another tool: it never edits `Info.plist`,
  never re-signs, and never needs `sudo`. It does not hide Spotify either —
  that is still `hide`/`install.sh`.

### `status --json` contract

`headless-spotify status --json` prints one JSON object on stdout. The exit
code is the same as plain `status` (0 only when ready), so read stdout even
on exit 1.

```json
{"app":"/Applications/Spotify.app","backup_present":false,"bundle":"com.spotify.client","dock":"visible","headless":false,"installed":true,"lsui_element":null,"player_state":"playing","ready":false,"running":true,"schema":1,"scriptable":true}
```

| Field | Type | Meaning |
|---|---|---|
| `schema` | int | Contract version, currently `1` |
| `app` | string | Path to Spotify.app that was checked |
| `bundle` | string | Always `com.spotify.client` |
| `installed` | bool | Spotify.app and its `Info.plist` exist |
| `running` | bool | A `Spotify` process is running |
| `lsui_element` | bool or null | `LSUIElement` in `Info.plist`; null when absent or not installed |
| `dock` | string | `visible`, `hidden`, `prohibited` or `notRunning` |
| `headless` | bool | `lsui_element` is true or `dock` is `hidden` |
| `player_state` | string or null | `playing`/`paused`/`stopped`; null when not running or not answering |
| `scriptable` | bool | `player_state` is not null |
| `backup_present` | bool | An `Info.plist` backup from `hide` exists |
| `ready` | bool | installed, running, headless and scriptable |

Versioning rules: new fields may be added under `schema` 1, so ignore keys
you do not know. Renaming, removing or changing the type of a field bumps
`schema`. The test suite pins the schema-1 fields
(`StatusJSONContractTests`).

## Troubleshooting

[⬆ Back to top](#headless-spotify)

| Symptom | Cause | Fix |
|---|---|---|
| `brew install kathir-d/tap/headless-spotify` installs nothing you can see | That was a formula, up to `0.1.0-beta.2`; a formula cannot put a bundle in `/Applications` | It is a cask now: `brew uninstall kathir-d/tap/headless-spotify && brew install --cask kathir-d/tap/headless-spotify` |
| No `headless-spotify` icon in the top bar after installing | The `postflight` launch failed, or the app was quit | `open /Applications/headless-spotify.app` |
| Clicking **Hidden from Dock** pops up "Apple could not verify 'headless-spotify' is free of malware", and the menu then does nothing | Fixed in `0.1.0-beta.4`. Before that, the cask cleared Gatekeeper's quarantine from the app but not from the CLI it links into `$(brew --prefix)/bin`, and a menu bar app is a GUI process — a GUI process running a quarantined binary hangs inside `dyld` behind that alert | Upgrade, or reinstall: `brew reinstall --cask kathir-d/tap/headless-spotify`. From `0.1.0-beta.4` the app also repairs a leftover-quarantine CLI by itself before running it |
| `hide` exits 1, Spotify won't stay launched headless | Spotify ≥1.3.1 quits when `LSUIElement=true` is present | Run `headless-spotify restore`; track Spotify releases — no code change needed if they honor the key again |
| Dock icon back after Spotify update | Updates rewrite `Info.plist` | Watcher re-applies automatically; or re-run `headless-spotify hide` |
| Opening Sonar brings Spotify back into the Dock | Same Spotify ≥1.3.1 limitation: Sonar launches Spotify, Spotify quits on launch with `LSUIElement` set, and the rollback restores a normal Dock icon | Nothing to undo — the cask skips the edit on a blocked Spotify, so there is nothing to roll back. See [If Spotify is still in the Dock](#if-spotify-is-still-in-the-dock) |
| A row says **Allow control of Spotify** and clicking it does nothing | macOS already refused once and will not prompt again | System Settings › Privacy & Security › Automation › headless-spotify |
| `hide` says bundle not writable | Root-owned `/Applications` copy | The cask already ran the privileged step; if you got here from a tarball, run `sudo ./install.sh /Applications/Spotify.app` |
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
sudo /Applications/headless-spotify.app/Contents/Resources/uninstall.sh /Applications/Spotify.app
brew uninstall --cask headless-spotify
```

Run the first line **before** the second, while the app — and with it the script
— is still there. It restores the original `Info.plist` + seal (Apple's
signature verifies again), relaunches Spotify normally, unloads/removes the
watcher agent, quits and removes the menu bar app, and removes the CLI + dylib.
The watcher and the menu bar app are stopped *first*, so a running daemon
cannot re-hide Spotify mid-uninstall. Your Dock icon comes back; nothing else
changes.

`brew uninstall --cask` on its own removes the app, the binary link and the
Caskroom — and it does **not** touch Spotify. Uninstalling the app before
restoring the bundle leaves a Spotify that will not launch, so do the first
command first.

From a tarball or a checkout it is the same script one directory up:

```sh
sudo ./uninstall.sh /Applications/Spotify.app   # sudo only if the bundle is root-owned
```

## Developing

[⬆ Back to top](#headless-spotify)

```sh
swift build          # CLI + injector dylib + menu bar extra (Command Line Tools are enough)
swift test           # 87 tests in 23 suites, all offline-safe (fixtures, stubbed runners)
./scripts/smoke-test.sh            # pre-release gate (pass --live to exercise real media controls)
./scripts/build-menubar.sh          # menu bar app bundle (debug: CONFIG=debug)
./scripts/package-release.sh       # versioned tarball + SHA256SUMS.txt (see VERSION)
./scripts/stage-cask-for-ci.sh     # rewrite Casks/*.rb against dist/ into a local tap
./scripts/check-cask-install.sh <owner>/<tap>/<cask>   # install the cask, assert what landed
```

`swift test` needs full Xcode (the Command Line Tools ship no test framework). With Xcode installed but not selected, run it via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

Layout: `Sources/HeadlessSpotify/*` (CLI), `Sources/HeadlessSpotifyBar/*` +
`Sources/HeadlessSpotifyBarKit/*` (menu bar extra), `Sources/CHeadlessInjector/*`
(dylib), `Tests/HeadlessSpotifyTests/*`, `install.sh` / `uninstall.sh`,
`launchagent/*.plist`, `Casks/headless-spotify.rb`,
`scripts/package-release.sh` + `scripts/smoke-test.sh`.

## Contributing

[⬆ Back to top](#headless-spotify)

Issues and small PRs welcome. Conventional commits (`feat:`, `fix:`, `docs:`,
`test:`, `chore:`), `git status` before committing. Before opening a PR,
run `swift build`, `swift test` (full Xcode), and `./scripts/smoke-test.sh`.

## Publishing to Homebrew

The cask lives in this repo at [`Casks/headless-spotify.rb`](Casks/headless-spotify.rb). Its
`version` and `sha256` are rewritten automatically by
[`.github/workflows/release.yml`](.github/workflows/release.yml) on every `v*` tag — never hand-edit
them, or CI will overwrite your change on the next release. The `url` interpolates `#{version}`, so
it needs no rewriting.

The same run copies the cask into the tap,
[`Kathir-D/homebrew-tap`](https://github.com/Kathir-D/homebrew-tap), which is what `brew install`
reads, and removes the old `Formula/headless-spotify.rb` from it — a tap that still has both would
keep resolving the bare name to the formula, which is the install that shows the user nothing. It
pushes with `TAP_DEPLOY_KEY`, a repository secret holding a deploy key that can write to that tap
and nothing else. If the step fails, the release is already up: fix the secret and re-run the job.

A cask has no `test do` block, so the checks the old formula's test block used to make live in
CI instead: `scripts/check-cask-install.sh` installs the cask into a throwaway tap and asserts
the bundle is in `/Applications`, `LSUIElement` is set, the privileged helpers are bundled and
executable, the CLI is on `PATH` at the right version with no stray copy in `/usr/local/bin`, the
signature still verifies, and the menu bar extra is actually running. Verify a release with:

```sh
brew update
brew upgrade --cask kathir-d/tap/headless-spotify   # or `brew install --cask` the first time
brew audit --cask --strict kathir-d/tap/headless-spotify
brew style --except Cask/InstallSteps kathir-d/tap/headless-spotify
```

`brew style` reports exactly one offense on the cask, `Cask/InstallSteps` on the `postflight`
block, and it cannot be resolved — Homebrew requires `postflight_steps`, whose DSL exposes no way
to run a command, and forbids suppressing the cop. The cask says so at length where the block is;
the second command above is the one that checks everything else. `brew audit --cask --strict`, the
gate Homebrew actually enforces, passes.

> **Why a cask and not a formula?** `app` is cask-only. A formula cannot put a bundle in
> `/Applications`, which is the entire reason the menu bar extra used to sit in the Cellar until
> somebody read a `sudo` command out of a tap README. A cask carries the CLI fine — `binary` is a
> first-class cask stanza — so nothing was traded away except `brew test`, which is why
> `scripts/check-cask-install.sh` exists.
>
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
