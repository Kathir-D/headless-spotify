// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// AppleScript probing of Spotify via /usr/bin/osascript. Sonar matches
// Spotify by bundleID + `player state`; these helpers use exactly that
// contract, so anything verified here holds for Sonar too.
//
// IMPORTANT: `playerState` never launches Spotify as a side effect — callers
// check `isSpotifyRunning` (pgrep, permission-free) first. Only the
// post-launch poll in `hide` talks to a Spotify we started ourselves.

import Foundation

public enum SpotifyScripting: Sendable {
    public static let bundleID = "com.spotify.client"

    public typealias Runner = @Sendable (String, [String]) -> ProcessResult

    /// Permission-free running check. `-x` matches exactly "Spotify", so the
    /// "Spotify Helper" processes never match.
    public static func isSpotifyRunning(run: Runner = ProcessRunner.run) -> Bool {
        run("/usr/bin/pgrep", ["-x", "Spotify"]).exitCode == 0
    }

    /// One-shot `player state` (playing|paused|stopped). nil when Spotify is
    /// not running or not scriptable yet.
    public static func playerState(run: Runner = ProcessRunner.run) -> String? {
        guard isSpotifyRunning(run: run) else { return nil }
        let result = run("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to get player state"])
        guard result.exitCode == 0 else { return nil }
        let state = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.isEmpty ? nil : state
    }

    /// Poll until Spotify answers AppleScript or `timeout` seconds elapse.
    /// Returns the first answered player state, or nil on timeout.
    public static func waitForScripting(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.5,
        run: Runner = ProcessRunner.run,
        sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let state = playerState(run: run) { return state }
            sleep(min(pollInterval, max(0, deadline.timeIntervalSinceNow)))
        }
        return playerState(run: run)
    }

    /// Ad-hoc re-sign after a plist edit (Apple Silicon refuses to relaunch a
    /// bundle whose seal no longer matches). Breaks Spotify's original
    /// signature — `restore` puts the original files back.
    public static func resignAdHoc(appPath: String, run: Runner = ProcessRunner.run) -> ProcessResult {
        run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appPath])
    }

    /// Verify the bundle seal (used after restore to prove the original
    /// Apple signature is back).
    public static func verifySignature(appPath: String, run: Runner = ProcessRunner.run) -> ProcessResult {
        run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appPath])
    }
}
