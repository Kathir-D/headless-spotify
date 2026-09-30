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
  version "0.1.0-beta.4"
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
  # The Caskroom is cleared as well as the app, and that second path is not
  # tidiness — it is the actual bug this cask had. `binary` links
  # /opt/homebrew/bin/headless-spotify at the copy Homebrew staged in the
  # Caskroom, which is *outside* the .app, so clearing the bundle left that
  # binary quarantined. The menu bar extra is a GUI process, and a GUI process
  # exec'ing a quarantined binary is the one case that trips Gatekeeper's
  # assessment: dyld blocks inside _dyld_start, CoreServicesUIAgent puts up
  # "Apple could not verify "headless-spotify" is free of malware", and the
  # Enable/Disable row hangs forever with no output. Running the same binary
  # from a terminal does not prompt, which is why the CLI's own `--version`
  # check in scripts/check-cask-install.sh passed for as long as it existed and
  # the bug shipped anyway. Sonar never hit this because it is `app` only:
  # everything it installs lives inside the one bundle cleared here.
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
      # The staged tree the `binary` stanza linked into the Homebrew prefix.
      # `caskroom_path` is <HOMEBREW_CASKROOM>/headless-spotify; clearing it
      # recursively covers bin/headless-spotify, the injector dylib, and the
      # helper scripts, and costs one call. must_succeed stays false because a
      # Homebrew that has dropped the accessor should not fail the install.
      system_command(
        "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", caskroom_path.to_s],
        must_succeed: false,
      )
      system_command(
        "/usr/bin/open",
        args:         ["-g", "/Applications/headless-spotify.app"],
        must_succeed: false,
      )
      # The privileged step, done here so `brew install --cask` is the only
      # command a user ever types.
      #
      # It used to be a line in the caveats, which meant the app installed, the
      # menu bar icon appeared, and nothing at all happened until the user read
      # forty lines of prose to discover there was a second command. A user who
      # never runs it gets a menu bar extra that does nothing, with no way to
      # tell that from a broken one.
      #
      # Gated on the Spotify version, and the gate is the whole point. Hiding
      # works by setting LSUIElement in Spotify's Info.plist and ad-hoc
      # re-signing the bundle. Spotify 1.3.1 and newer quit on launch whenever
      # that key is present, so the edit is guaranteed to fail there: install.sh
      # rolls the plist back and carries on. What it cannot roll back is the
      # re-sign, because a bundle cannot be given back Spotify's Developer ID
      # signature by anything on this machine. So running the edit against a
      # blocked Spotify costs the user a bundle that fails `codesign -v`, in
      # exchange for nothing at all.
      #
      # So: below 1.3.1, where hiding can actually work, it is done for them.
      # At or above it, nothing is touched and one line says why. Comparing with
      # Gem::Version rather than string comparison, because "1.3.10" sorts
      # before "1.3.9" as a string.
      spotify_version = begin
        plist = "/Applications/Spotify.app/Contents/Info.plist"
        system_command(
          "/usr/libexec/PlistBuddy", args: ["-c", "Print :CFBundleShortVersionString", plist]
        )&.stdout&.strip
      rescue
        nil
      end
      hiding_blocked = begin
        Gem::Version.new(spotify_version) >= Gem::Version.new("1.3.1")
      rescue
        # An unknown version is treated as blocked. Guessing wrong the other way
        # would mean re-signing a user's Spotify on a hunch.
        !spotify_version.nil?
      end

      if hiding_blocked
        ohai "Spotify #{spotify_version || "version unknown"} quits when LSUIElement is set, " \
             "so hiding is not being applied. Everything else is installed and working."
      else
        # `/usr/bin/sudo` as the executable rather than `sudo: true` on the
        # system_command, because install.sh insists on being invoked *through*
        # sudo: it needs SUDO_USER to relaunch Spotify as the console user
        # rather than as root, which would hand it the wrong session.
        #
        # must_succeed stays false so a user who declines the password prompt,
        # or has no sudo rights, still ends up with a working app and CLI.
        system_command(
          "/usr/bin/sudo",
          args:         [
            "/Applications/headless-spotify.app/Contents/Resources/install.sh",
            "/Applications/Spotify.app",
          ],
          must_succeed: false,
        )
      end
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
    That was the whole install. Look for the music note in the top bar: its menu
    has a Hide-from-Dock toggle, and it will offer to ask macOS for permission
    the first time it needs it.

    If Spotify is still in the Dock, nothing is broken — Spotify 1.3.1 and newer
    quit on launch when that is asked of them, so the edit was skipped rather
    than applied and then half-undone. `headless-spotify status` says which.
  EOS
end
