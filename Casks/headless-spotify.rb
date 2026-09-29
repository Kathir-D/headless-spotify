# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# Homebrew cask for headless-spotify. Ships the prebuilt universal CLI and the
# menu bar extra from the GitHub release tarball (built by
# scripts/package-release.sh).
#
# A cask and not a formula, for one reason: `app` is cask-only. A formula
# cannot put a bundle in /Applications, which is exactly why the menu bar extra
# used to sit in the Cellar until somebody read a sudo command out of a README
# to discover it existed. `brew install --cask` now leaves a working top-bar
# icon, and the privileged Spotify edit stays behind install.sh as the only
# thing that needs sudo.
#
# The cask is only `app` + `binary` on purpose. The bundle carries install.sh,
# uninstall.sh and the injector dylib in its own Contents/Resources, so
# `brew install` moves one thing and the one privileged command is still
# somewhere findable at a path that does not change between versions.
#
# NOTE: `version` and `sha256` are refreshed by CI
# (.github/workflows/release.yml) on every `v*` tag, which also copies this
# file into the Kathir-D/homebrew-tap tap — do not hand-edit them.
cask "headless-spotify" do
  version "0.1.0-beta.3"
  sha256 "2430b62084e3e1c2a116f68e27cbda630e2f0de9d6b4d07e45371ea10054189b"

  url "https://github.com/Kathir-D/headless-spotify/releases/download/v#{version}/headless-spotify-#{version}-macos.tar.gz"
  name "headless-spotify"
  desc "Hide Spotify from the Dock and Cmd-Tab, with a top-bar toggle"
  homepage "https://github.com/Kathir-D/headless-spotify"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  # The release tarball unpacks into a versioned top-level directory. Formulae
  # descend into that automatically; casks do not, so every source below spells
  # the directory out.
  app "headless-spotify-#{version}/headless-spotify.app"
  binary "headless-spotify-#{version}/bin/headless-spotify"

  uninstall quit: "com.headless-spotify.bar"

  # Ad-hoc signed and not notarized, so Gatekeeper would otherwise make every
  # user approve the app by hand in System Settings on first launch. Then start
  # it, because a menu bar extra nobody has to find is the same as one that was
  # never installed.
  #
  # `brew install` has already verified the SHA-256 above before any of this
  # runs, so the checksum is the integrity gate and the quarantine attribute is
  # no longer what stands between the user and an app they knowingly installed
  # from this tap. `brew install --no-quarantine` would say the same thing, but
  # it was removed in Homebrew 7 and `postflight_steps` cannot run a command.
  #
  # The rescue matters. Without it, removing `postflight` would not merely stop
  # the quarantine from being cleared — it would make the cask file invalid, and
  # an invalid cask stops the whole tap from loading, so `brew tap` would fail
  # and nobody could install anything. Rescued, the worst case is that users get
  # the normal one-time Gatekeeper approval again.
  #
  # `brew style` reports one offense on the block below, Cask/InstallSteps, and
  # it cannot be resolved: Homebrew requires postflight_steps, whose DSL exposes
  # only if_path_exists, on_macos, version and token and cannot run a command at
  # all; and Style/DisableCopsWithinSourceCodeDirective forbids suppressing the
  # cop. The two rules together make the requirement unsatisfiable, so the block
  # stays and the offense stays. Check the cask with the cop excluded:
  #   brew style --except Cask/InstallSteps kathir-d/tap/headless-spotify
  # `brew audit --cask --strict`, the gate Homebrew actually enforces, passes.
  begin
    postflight do
      system_command(
        "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "/Applications/headless-spotify.app"],
        must_succeed: false,
      )
      system_command(
        "/usr/bin/open",
        args:         ["-g", "/Applications/headless-spotify.app"],
        must_succeed: false,
      )
    end
  rescue NoMethodError
    # Homebrew dropped the postflight block. Nothing to do; the install itself
    # still succeeds, the user just approves the app once themselves.
  end

  zap trash: [
    "~/Library/Application Scripts/com.headless-spotify.bar",
    "~/Library/Caches/com.headless-spotify.bar",
    "~/Library/HTTPStorings/com.headless-spotify.bar",
    "~/Library/LaunchAgents/com.headless-spotify.watcher.plist",
    "~/Library/Logs/headless-spotify",
    "~/Library/Preferences/com.headless-spotify.bar.plist",
  ]

  caveats <<~EOS
    The menu bar extra is installed and running: look for the headless-spotify
    icon in the top bar. Its menu shows the version, an Enable/Disable hiding
    toggle and Quit.

    Nothing has touched Spotify yet, and that is deliberate. Hiding edits a
    root-owned, signed system bundle, so it is the one step that needs sudo:

      sudo /Applications/headless-spotify.app/Contents/Resources/install.sh

    That also loads the watcher LaunchAgent so hiding survives Spotify updates
    and restarts.

    Blocked on Spotify >= 1.3.1 (verified 2026-09-28, macOS 26): Spotify quits
    on launch whenever LSUIElement is present in its Info.plist, so on a current
    Spotify the command above will finish installing, report that hiding did not
    verify, roll your Info.plist back, leave Spotify running normally, and skip
    the watcher. Nothing is broken; hiding simply does not take effect yet. The
    menu bar icon, `headless-spotify status` and `headless-spotify restore` all
    keep working. If Spotify ever honors LSUIElement again, no code change is
    needed — only the notice in the README.

    Afterwards:
      headless-spotify status     # Dock? LSUIElement? player state?
      headless-spotify restore    # back to normal, any time
      headless-spotify watch --uninstall-agent   # stop the watcher only

    To undo everything before `brew uninstall --cask headless-spotify`:
      sudo /Applications/headless-spotify.app/Contents/Resources/uninstall.sh
  EOS
end
