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
  sha256 "b8baaf3d4e7b4c17f7bd1d2cf56c97b9bd766019d2d04114cdb52a7902cf0aeb"

  depends_on macos: :sequoia

  def install
    bin.install "bin/headless-spotify"
    lib.install "lib/libHeadlessSpotifyInjector.dylib"
    prefix.install %w[install.sh uninstall.sh VERSION LICENSE README.md THIRD-PARTY-NOTICES.md]
    (prefix/"launchagent").install "launchagent/com.headless-spotify.watcher.plist"
  end

  def caveats
    <<~EOS
      headless-spotify needs the official Spotify.app (Free tier works):
        brew install --cask spotify  # or download from spotify.com

      Hide it (needs write access to Spotify.app; uses sudo only via install.sh):
        headless-spotify hide
      Back to normal any time:
        headless-spotify restore
      Keep it headless across Spotify updates + restarts:
        headless-spotify watch --install-agent

      Known limits (see README): Spotify >= 1.3.1 currently exits when
      LSUIElement is set, and its hardened runtime ignores the injector
      dylib. `status`/`hide` report this honestly.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/headless-spotify --version")
    # Missing bundle: usage error (exit 2), no Spotify needed for the test.
    output = shell_output("#{bin}/headless-spotify hide --dry-run --spotify-app /nonexistent/Spotify.app 2>&1", 2)
    assert_match "not found", output
  end
end
