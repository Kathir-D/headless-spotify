# headless-spotify — Implementation TODO

> Hide official macOS Spotify (`com.spotify.client`) from Dock + Cmd-Tab while keeping windows + AppleScript working, so Sonar controls it identically to normal Spotify.

## 0. Context / why this approach

- Rejected `librespot` (Premium-only) and `Soloist` (Linux-only + Premium API key). This project hides the official app — **no Premium, no API key, no long setup**, Free tier works.
- Method 1 (simple): `defaults write .../Spotify.app/Contents/Info.plist LSUIElement true` (from `4ian/hide-spotify-from-dock`, MIT). Fragile: wiped on Spotify updates, breaks Spotify code signature.
- Method 2 (robust fallback): force `setActivationPolicy: → Accessory` injector + watcher (concept from `hide-macos-app-dock-icon`, MIT). Survives restarts, removes Dock + switcher, keeps windows.
- Do both with fallback: try plist, fall back to injector when Dock returns.

## 1. Hard rules

1. **Licenses:** both upstream tricks are MIT — keep attribution in `THIRD-PARTY-NOTICES.md`. New code MIT (c) 2026.
2. **Spotify contract (shared with Sonar):** process stays `com.spotify.client`, scripting dictionary intact. Sonar matches by bundleID + `player state` only. Never rename process, never break `tell application "Spotify"`.
3. **Headless launch:** `NSWorkspace.openApplication(activates:false)`, wait ≤10 s for AppleScript response before reporting ready.
4. **Safety:** `install.sh` backs up Info.plist; `uninstall.sh` restores; never commit API keys/certs; `sudo` only for install step.
5. **Commits:** conventional, small, `git status` first.

## 2. Task list (in order)

### [ ] 1. `chore: init SPM CLI`
- Why: testable foundation for installer/launcher logic.
- Do: `Package.swift` (macOS 15 executable `headless-spotify`), `Sources/HeadlessSpotify/main.swift` (`status|hide|restore` subcommands stub), `install.sh`/`uninstall.sh` stubs, `launchagent/` stub; `swift build` + `swift test` green.
- Done when: `--help` works, stubs committed.

### [ ] 2. `feat: LSUIElement mode + ensure-running launcher`
- Why: 80% case, one-line fix.
- Do: backup plist, `defaults write ... LSUIElement true`, re-sign note (ad-hoc breaks Spotify sig — document), restart Spotify headless, poll `player state` ≤10 s, `status` verifies Dock absence + scriptability.
- Done when: Spotify runs with no Dock, Sonar `player state` + play/pause/volume work, `restore` brings Dock back.

### [ ] 3. `feat: injector fallback + watcher + persistence`
- Why: Spotify overrides plist / updates wipe it.
- Do: injector dylib forcing Accessory; detect Dock-return → auto-fallback; LaunchAgent watcher re-applies after updates; `SMAppService` login-item option; document Accessibility/permissions if needed.
- Done when: kill-and-relaunch + simulated update keeps app headless; windows usable; Cmd-Tab clean.

### [ ] 4. `docs: README + NOTICES + compat matrix`
- Why: fresh rewrite required.
- Do: install/uninstall, verify (`tell application "Spotify" to get player state`), troubleshooting (update wipes, re-sign, TCC), Credits table, Sonar compat matrix (normal / plist-headless / injector-headless × play/pause/volume/track).
- Done when: fresh Mac follows README with no extra help.

## 3. Test matrix

- Fresh install → hide → Sonar controls → Spotify self-update → still hidden → uninstall → Dock restored. Test Free + Premium accounts (both must work).

## 4. Key files

- `Sources/HeadlessSpotify/*`, `install.sh`, `uninstall.sh`, `launchagent/*.plist`, `THIRD-PARTY-NOTICES.md`

## 5. Homebrew + prod (formula, in same tap as Sonar)

Why: `brew install headless-spotify` (CLI) pairs with `brew install --cask sonar`.

### [ ] 5. `feat: release packaging (tarball + checksums)`
- Do: `scripts/package-release.sh` → versioned tarball + `SHA256SUMS.txt` from git tag (`VERSION` file is source of truth); keep ad-hoc dev lane + signed release lane.
- Done when: tarball installs on clean VM, `headless-spotify status` works.

### [ ] 6. `feat: homebrew-tap formula`
- Do: in `homebrew-tap` repo add `Formula/headless-spotify.rb` (url+sha256 of release tarball, `depends_on macos`, binary install + `launchagent` handling notes, `caveats` about `sudo ./install.sh` + Spotify-update watcher); `brew audit --strict`, `brew install/test/uninstall` on fresh user; CI bumps formula on every GitHub Release.
- Done when: `brew tap you/tap && brew install headless-spotify && headless-spotify hide` works from scratch, uninstall restores Dock.
