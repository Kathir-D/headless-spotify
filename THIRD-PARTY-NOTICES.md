# Third-Party Notices — headless-spotify

New code in this repo is MIT (c) 2026 headless-spotify Contributors (see LICENSE).

## Upstream sources

### 4ian/hide-spotify-from-dock — MIT 2016 Florian Rival
- URL: https://github.com/4ian/hide-spotify-from-dock
- License: MIT (Copyright (c) 2016 Florian Rival).
- Used: the `defaults write … LSUIElement true` + restart approach (here:
  `SpotifyPlist.setLSUIElement`, `install.sh`, `Runner.hide`), with backup /
  restore / re-sign handling added. Attribution kept in README + code comments.

### michaelmitchell-bit/hide-macos-app-dock-icon — MIT
- URL: https://github.com/michaelmitchell-bit/hide-macos-app-dock-icon
- License: MIT.
- Used: the concept of forcing `setActivationPolicy:` to `Accessory` from an
  injected module (here: re-implemented from scratch as
  `Sources/CHeadlessInjector/injector.m`, bundle-ID-gated to
  `com.spotify.client`). Attribution kept in README + code comments.

### Spotify Soloist / librespot — NOT used
- Soloist is Linux-only + requires a Premium API key. librespot is
  Premium-only.
- Rejected: this project hides the official macOS Spotify.app instead (no
  Premium, no API key, Free tier works).

## Dependencies

None. The Swift package uses only the macOS SDK (Foundation/AppKit) and the
C standard library — there are no third-party packages to attribute.
