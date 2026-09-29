// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Injector fallback: locate the accessory-policy dylib and relaunch Spotify
// with DYLD_INSERT_LIBRARIES. Best-effort by design — hardened-runtime hosts
// strip DYLD_* vars (current official Spotify.app does), in which case the
// caller falls through and the watcher keeps plist mode primary.

import Foundation

public enum HideMode: String, Sendable, CaseIterable {
    /// Plist first, injector when the Dock icon survives.
    case auto
    case plist
    case injector
}

public enum Injector: Sendable {
    public static let dylibFileName = "libHeadlessSpotifyInjector.dylib"
    public static let installedPath = "/usr/local/lib/headless-spotify/libHeadlessSpotifyInjector.dylib"
    public static let envOverride = "HEADLESS_INJECTOR_DYLIB"

    /// Resolution order: --injector flag > $HEADLESS_INJECTOR_DYLIB >
    /// /usr/local/lib/headless-spotify/… > paths relative to the CLI binary
    /// (dev side-by-side, Homebrew bin/../lib, /usr/local layout).
    public static func locate(explicit: String?, cliBinaryPath: String? = nil) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        if let env = ProcessInfo.processInfo.environment[envOverride], !env.isEmpty { return env }
        if FileManager.default.fileExists(atPath: installedPath) { return installedPath }
        if let cli = cliBinaryPath {
            let dir = URL(fileURLWithPath: cli).deletingLastPathComponent()
            for candidate in [
                dir.appendingPathComponent(dylibFileName),
                dir.appendingPathComponent("../lib/\(dylibFileName)"),
                dir.appendingPathComponent("../lib/headless-spotify/\(dylibFileName)"),
            ] {
                let path = candidate.standardized.path
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Parse `codesign -dv` output: flags=0x10000(runtime) means hardened.
    public static func isHardenedRuntime(appPath: String, run: SpotifyScripting.Runner = ProcessRunner.run) async -> Bool {
        let result = await run("/usr/bin/codesign", ["-dv", appPath], 30)
        let combined = result.stdout + "\n" + result.stderr
        for line in combined.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("flags="), text.contains("(runtime)") else { continue }
            return true
        }
        return false
    }
}
