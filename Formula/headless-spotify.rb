# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# Homebrew formula for headless-spotify. Ships the prebuilt universal CLI +
# injector dylib from the GitHub release tarball (built by
# scripts/package-release.sh). NOTE: `url`/`sha256` are refreshed by CI
# (.github/workflows/release.yml) on every `v*` tag, which also copies this
# file into the Kathir-D/homebrew-tap tap — do not hand-edit them.
class HeadlessSpotify < Formula
  desc "Hide official Spotify from Dock + Cmd-Tab, keep AppleScript control"
  homepage "https://github.com/Kathir-D/headless-spotify"
  url "https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0-beta.2/headless-spotify-0.1.0-beta.2-macos.tar.gz"
  sha256 "eca00778f2e04c08d34bebfc39209ba1c4e8bcd13b8b69723c9f667f4113ad92"
  license "MIT"

  depends_on macos: :sequoia

  def install
    bin.install "bin/headless-spotify"
    lib.install "lib/libHeadlessSpotifyInjector.dylib"
    # The menu bar app stays in the Cellar: the `app` DSL is cask-only, and
    # writing to /Applications is a cask's job. install.sh (below) copies it
    # into /Applications when you run it. `prefix.install` (not
    # `prefix/"x.app".install`) — the latter would nest the bundle inside a
    # directory of the same name.
    prefix.install "headless-spotify.app"
    # install.sh finds bin/, lib/ and the .app next to itself, so it has to
    # live at the top of the keg with them. Under share/ it found none of them
    # and fell through to `swift build` in a directory with no Package.swift.
    prefix.install "install.sh", "uninstall.sh"
    (prefix/"share/headless-spotify").install %w[VERSION README.md LICENSE THIRD-PARTY-NOTICES.md]
    (prefix/"launchagent").install "launchagent/com.headless-spotify.watcher.plist"
  end

  def caveats
    <<~EOS
      headless-spotify needs the official Spotify.app (Free tier works):
        brew install --cask spotify  # or download from spotify.com

      Nothing has touched Spotify yet. To hide it (this is the step that edits
      the bundle, and the only one that needs sudo):
        sudo "$(brew --prefix headless-spotify)/install.sh"

      That also copies the menu bar app from
        $(brew --prefix headless-spotify)/headless-spotify.app
      to /Applications/headless-spotify.app, and loads the watcher LaunchAgent.

      To undo all of it before `brew uninstall headless-spotify`:
        "$(brew --prefix headless-spotify)/uninstall.sh"

      Afterwards:
        headless-spotify status     # Dock? LSUIElement? player state?
        headless-spotify restore    # back to normal, any time
        headless-spotify watch --uninstall-agent   # stop the watcher only

      Known limits (see README): Spotify >= 1.3.1 currently exits when
      LSUIElement is set, and its hardened runtime ignores the injector dylib.
      On those versions install.sh rolls the bundle back, leaves Spotify
      untouched, and skips the watcher.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/headless-spotify --version")
    # Missing bundle: usage error (exit 2), no Spotify needed for the test.
    output = shell_output("#{bin}/headless-spotify hide --dry-run --spotify-app /nonexistent/Spotify.app 2>&1", 2)
    assert_match "not found", output
    # Menu bar extra ships with the formula; install.sh puts it in /Applications.
    info = prefix/"headless-spotify.app/Contents/Info.plist"
    assert_path_exists info
    assert_equal "true", shell_output("/usr/libexec/PlistBuddy -c 'Print :LSUIElement' '#{info}'").strip
    # The install helper that does the privileged work must be present.
    # It sits next to bin/, lib/ and the .app, which is where it looks for them.
    assert_path_exists prefix/"install.sh"
    assert_path_exists prefix/"bin/headless-spotify"
    assert_path_exists prefix/"lib/libHeadlessSpotifyInjector.dylib"
  end
end
