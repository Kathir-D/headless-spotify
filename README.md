# headless-spotify

Run official Spotify on macOS with no Dock icon and no Cmd-Tab entry. Windows still work. AppleScript still works, so Sonar controls it identically to normal Spotify.

No Premium, no API key, no Soloist/librespot. Soloist is Linux-only + needs a Premium API key; librespot is Premium-only — both rejected for this macOS goal.

## How it works

Two hiding methods, tried in order (`hide --mode auto`, the default):

1. **LSUIElement mode (primary).** Sets `LSUIElement=true` in
   `/Applications/Spotify.app/Contents/Info.plist`, ad-hoc re-signs (Apple
   Silicon refuses to relaunch an edited bundle otherwise), then relaunches
   Spotify headless (`NSWorkspace.openApplication(activates:false)`) and polls
   `player state` for up to 10 s. Concept credit:
   [4ian/hide-spotify-from-dock](https://github.com/4ian/hide-spotify-from-dock) (MIT).
2. **Injector fallback.** If the Dock icon survives plist mode, Spotify is
   relaunched with `DYLD_INSERT_LIBRARIES` pointing at
   `libHeadlessSpotifyInjector.dylib`, whose constructor forces
   `setActivationPolicy: → Accessory`. Concept credit:
   [michaelmitchell-bit/hide-macos-app-dock-icon](https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon) (MIT).
   **Known limit:** hardened-runtime binaries (current official Spotify.app)
   strip `DYLD_*` variables at exec, so the injector is ignored there and plist
   mode stays primary. The dylib is bundle-ID gated to `com.spotify.client`,
   so it can never alter your other apps.

A **watcher daemon** (`headless-spotify watch`, kept alive by a LaunchAgent)
re-applies hiding when Spotify self-updates (updates wipe `Info.plist`) or the
Dock icon returns: stale launch → relaunch headless; wiped plist → redo
plist + re-sign + relaunch; Dock survives plist mode → injector.

The Spotify contract never changes: the process stays `com.spotify.client`
and the scripting dictionary stays intact. Sonar matches by bundleID +
`player state` only — never by Dock or window presence.

## Install

```sh
git clone <this-repo> && cd headless-spotify
sudo ./install.sh /Applications/Spotify.app
```

What it does: builds the release CLI + dylib, installs them to
`/usr/local/bin` and `/usr/local/lib/headless-spotify/`, backs up
`Info.plist` (+ the code-seal file), sets `LSUIElement=true`, ad-hoc
re-signs, relaunches Spotify headless as you, verifies `player state`, and
loads the watcher LaunchAgent. `sudo` is needed only here (bundle edit +
system paths) — the CLI itself never needs root.

No Xcode project required — just the Xcode Command Line Tools (`swift`).

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
```

## Uninstall

```sh
./uninstall.sh /Applications/Spotify.app   # sudo only if the bundle is root-owned
```

Restores the original `Info.plist` + seal (Apple's signature verifies again),
relaunches Spotify normally, unloads/removes the agent, removes the CLI +
dylib. Your Dock icon comes back; nothing else changes.

## Verify (works for normal + headless)

```applescript
tell application "Spotify" to get player state
--> playing / paused / stopped
```

Match by `bundleID == com.spotify.client`, never by Dock/window.

## Sonar compat matrix

| Spotify mode | Sonar sees it | Control |
|---|---|---|
| Normal | yes | play/pause/volume/track |
| Headless (`LSUIElement`) | yes | same |
| Headless (injector) | yes | same |

Both headless modes keep the same bundle ID and scripting dictionary, so
Sonar needs no changes between rows.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Dock icon back after Spotify update | Updates rewrite `Info.plist` | Watcher re-applies automatically; or re-run `headless-spotify hide` |
| `hide` says bundle not writable | Root-owned `/Applications` copy | Run `sudo ./install.sh` (the one sudo step) |
| Spotify won't launch after `hide` | Edited bundle, re-sign failed | Re-run `hide` (look for the re-sign error), or `restore` + reinstall Spotify |
| `restore` warns signature invalid | Seal files diverge (e.g. manual edits after backup) | Reinstall Spotify from spotify.com, then `hide` again |
| First `status`/`hide` prompts for automation access | macOS asks once before `osascript` may control Spotify | Allow it; afterwards everything is non-interactive |
| Injector seemingly does nothing | Hardened Spotify strips `DYLD_*` | Expected — plist mode is primary; see “Known limit” above |
| Watcher log | `/tmp/headless-spotify-watcher.log` | `headless-spotify status` tells current state |

Permissions note: no Accessibility permission is needed. The only prompt is
the one-time AppleEvents authorization for controlling Spotify, which Sonar
users have already granted.

## Credits & Provenance

| What | Source | Author | License | How used |
|---|---|---|---|---|
| `LSUIElement` trick | https://github.com/4ian/hide-spotify-from-dock | @4ian | MIT 2016 | Backup + set + restore, with attribution |
| Injector fallback concept | https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon | @michaelmitchell-bit | MIT | Re-implemented as bundle-ID-gated dylib, with attribution |
| Soloist / librespot | — | — | — | **Not used** (Linux-only / Premium-only) |

Full texts: see `THIRD-PARTY-NOTICES.md` + `LICENSE`.

## Developing

```sh
swift build          # CLI + injector dylib
swift test           # 31 tests, all offline-safe (fixtures, stubbed runners)
./scripts/package-release.sh   # versioned tarball + SHA256SUMS.txt (see VERSION)
```

## License

MIT — see `LICENSE`.
