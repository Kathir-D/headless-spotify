# headless-spotify

Run official Spotify on macOS with no Dock icon and no Cmd-Tab entry. Windows still work. AppleScript still works, so Sonar controls it identically to normal Spotify.

> Status: scaffold. `LSUIElement` mode + injector fallback land next.

No Premium, no API key, no Soloist/librespot. Soloist is Linux-only + needs Premium API key — rejected for this macOS goal.

## Methods

1. `LSUIElement=true` on `/Applications/Spotify.app/Contents/Info.plist` + restart headless (`activates:false`). Wiped on Spotify updates, breaks Spotify signature.
2. Fallback: force `setActivationPolicy: → Accessory` injector + watcher (survives updates, removes Dock + Cmd-Tab, keeps windows).

## Install

```sh
sudo ./install.sh /Applications/Spotify.app
# restart Spotify, verify no Dock icon
./uninstall.sh  # restore
```

## Verify (works for normal + headless)

```applescript
tell application "Spotify" to get player state
```

Match by `bundleID == com.spotify.client`, never by Dock/window.

## Sonar compat matrix

| Spotify mode | Sonar sees it | Control |
|---|---|---|
| Normal | yes | play/pause/volume/track |
| Headless (`LSUIElement`) | yes | same |
| Headless (injector) | yes | same |

## Credits & Provenance

| What | Source | Author | License | How used |
|---|---|---|---|---|
| `LSUIElement` trick | https://github.com/4ian/hide-spotify-from-dock | @4ian | MIT 2016 | 1-liner with attribution |
| Injector fallback concept | https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon | @michaelmitchell-bit | MIT | Adapted with attribution |

Full texts: see `THIRD-PARTY-NOTICES.md` + `LICENSE`.

## License

MIT — see `LICENSE`.
