# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# Homebrew formula for headless-spotify. Ships the prebuilt universal CLI +
# injector dylib from the GitHub release tarball (built by
# scripts/package-release.sh). NOTE: `sha256`/`version` are refreshed by CI
# (.github/workflows/release.yml) on every `v*` tag — do not hand-edit.
class HeadlessSpotify < Formula
  desc "Hide official Spotify from Dock + Cmd-Tab, keep AppleScript control"
  homepage "https://github.com/Kathir-D/headless-spotify"
  url "https://github.com/Kathir-D/headless-spotify/releases/download/v0.1.0/headless-spotify-0.1.0-macos.tar.gz"
  sha256 "93e55c768ed34ebeb3cb50c4c593e0412ae5cb7ea24e14a7c66ae9ae90043d13"
  license "MIT"

  depends_on macos: :sequoia

  def install
    bin.install "bin/headless-spotify"
    lib.install "lib/libHeadlessSpotifyInjector.dylib"
    app "headless-spotify.app" => "/Applications"
    prefix.install %w[install.sh uninstall.sh VERSION LICENSE README.md THIRD-PARTY-NOTICES.md]
    (prefix/"launchagent").install "launchagent/com.headless-spotify.watcher.plist"
  end

  def caveats
    <<~EOS
      headless-spotify needs the official Spotify.app (Free tier works):
        brew install --cask spotify  # or download from spotify.com

      The menu bar extra is installed to /Applications/headless-spotify.app.
      Launch it from Applications (or `open /Applications/headless-spotify.app`);
      its menu shows the project name and a Quit action.

      Hide it (needs write access to Spotify.app):
        sudo "$(brew --prefix)/share/headless-spotify/install.sh"
        # or, if /Applications/Spotify.app is already writable by you:
        headless-spotify hide
      Back to normal any time:
        headless-spotify restore
      Keep it headless across Spotify updates + restarts:
        headless-spotify watch --install-agent

      Known limits (see README): Spotify >= 1.3.1 currently exits when
      LSUIElement is set, and its hardened runtime ignores the injector
      dylib. `status`/`hide` report this honestly, and install.sh rolls the
      bundle back so Spotify keeps launching.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/headless-spotify --version")
    # Missing bundle: usage error (exit 2), no Spotify needed for the test.
    output = shell_output("#{bin}/headless-spotify hide --dry-run --spotify-app /nonexistent/Spotify.app 2>&1", 2)
    assert_match "not found", output
    # Menu bar extra: shipped in the tarball, installed into /Applications.
    menubar = "/Applications/headless-spotify.app"
    assert_path_exists "#{menubar}/Contents/Info.plist"
    plist = shell_output("/usr/libexec/PlistBuddy -c 'Print :LSUIElement' " \
                         "'#{menubar}/Contents/Info.plist'")
    assert_equal "true", plist.strip
  end
end
