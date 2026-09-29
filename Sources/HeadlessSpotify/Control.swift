// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Media-key passthroughs for a Dock-less Spotify. Same AppleScript contract
// Sonar uses (`tell application "Spotify" …"), so anything verified here
// holds for Sonar too. Never launches Spotify as a side effect: every action
// is gated on the pgrep running check first.

import Foundation

/// Actions for `headless-spotify control <action> [value]`.
public enum ControlAction: String, Sendable, CaseIterable {
    case play
    case pause
    /// Play/pause toggle (Spotify's `playpause` verb).
    case toggle
    case next
    case previous
    /// Print current sound volume (0–100).
    case volume
    /// Set sound volume (0–100, clamped).
    case setVolume = "set-volume"
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
}

public enum Control: Sendable {
    /// Spotify-side AppleScript for one action. `getVolume`/`setVolume` take
    /// two calls (read, clamp in Swift, write) so the step math is exact.
    public static func script(for action: ControlAction, value: Int? = nil, currentVolume: Int? = nil) -> String? {
        switch action {
        case .play: return "tell application \"Spotify\" to play"
        case .pause: return "tell application \"Spotify\" to pause"
        case .toggle: return "tell application \"Spotify\" to playpause"
        case .next: return "tell application \"Spotify\" to next track"
        case .previous: return "tell application \"Spotify\" to previous track"
        case .volume: return "tell application \"Spotify\" to get sound volume"
        case .setVolume:
            guard let value else { return nil }
            return "tell application \"Spotify\" to set sound volume to \(min(100, max(0, value)))"
        case .volumeUp:
            guard let currentVolume else { return nil }
            return "tell application \"Spotify\" to set sound volume to \(min(100, currentVolume + 10))"
        case .volumeDown:
            guard let currentVolume else { return nil }
            return "tell application \"Spotify\" to set sound volume to \(max(0, currentVolume - 10))"
        }
    }

    public static func getVolume(run: SpotifyScripting.Runner = ProcessRunner.run) async -> Int? {
        guard await SpotifyScripting.isSpotifyRunning(run: run) else { return nil }
        guard let script = script(for: .volume) else { return nil }
        let result = await run("/usr/bin/osascript", ["-e", script], 15)
        guard result.exitCode == 0 else { return nil }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Run one control action. Returns (exitCode, outputLine).
    public static func perform(
        _ action: ControlAction,
        value: Int? = nil,
        run: SpotifyScripting.Runner = ProcessRunner.run
    ) async -> (Int32, String) {
        guard await SpotifyScripting.isSpotifyRunning(run: run) else {
            return (1, "control: Spotify is not running — refusing to launch it (open Spotify or run `hide`/`restore`).")
        }
        let script: String?
        switch action {
        case .volumeUp, .volumeDown:
            guard let current = await getVolume(run: run) else {
                return (1, "control: could not read current volume.")
            }
            script = self.script(for: action, currentVolume: current)
        case .setVolume:
            guard value != nil else { return (2, "control: set-volume needs a value 0–100.") }
            script = self.script(for: action, value: value)
        default:
            script = self.script(for: action)
        }
        guard let script else { return (2, "control: could not build script for \(action.rawValue).") }
        let result = await run("/usr/bin/osascript", ["-e", script], 15)
        if result.exitCode != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (1, "control: \(action.rawValue) failed\(detail.isEmpty ? "" : ": \(detail)").")
        }
        switch action {
        case .volume:
            return (0, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        case .setVolume, .volumeUp, .volumeDown:
            return (0, "volume: \(await getVolume(run: run).map(String.init) ?? "?")")
        default:
            return (0, "\(action.rawValue): ok")
        }
    }
}
