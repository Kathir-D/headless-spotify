// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// CLI argument model for headless-spotify. Dependency-free (stdlib +
// Foundation/AppKit only) so the MIT-only rule stays trivial.

import Foundation

/// Subcommands. `watch` (task 3) runs the persistence daemon; the rest are
/// fully implemented in task 2.
public enum Subcommand: String, Sendable, CaseIterable {
    case status
    case hide
    case restore
    case watch
}

/// Parsed CLI invocation.
public struct Invocation: Sendable, Equatable {
    public var subcommand: Subcommand?
    public var showHelp: Bool
    public var showVersion: Bool
    public var spotifyAppPath: String
    /// Seconds to wait for AppleScript after (re)launch. Default 10 (TODO §1.3).
    public var timeout: TimeInterval
    /// `hide`: edit Info.plist but do not relaunch (used by install.sh, which
    /// relaunches as the console user afterwards).
    public var skipRelaunch: Bool
    /// `hide`/`restore`: skip the plist edit, only relaunch + verify.
    public var skipPlist: Bool
    /// `hide`: skip ad-hoc re-sign (relaunch will likely fail on Apple Silicon).
    public var noResign: Bool
    /// `status`: machine-readable output for Sonar/scripts.
    public var json: Bool
    /// Print the plan without changing anything.
    public var dryRun: Bool

    public init(
        subcommand: Subcommand? = nil,
        showHelp: Bool = false,
        showVersion: Bool = false,
        spotifyAppPath: String = CLI.defaultSpotifyAppPath,
        timeout: TimeInterval = 10,
        skipRelaunch: Bool = false,
        skipPlist: Bool = false,
        noResign: Bool = false,
        json: Bool = false,
        dryRun: Bool = false
    ) {
        self.subcommand = subcommand
        self.showHelp = showHelp
        self.showVersion = showVersion
        self.spotifyAppPath = spotifyAppPath
        self.timeout = timeout
        self.skipRelaunch = skipRelaunch
        self.skipPlist = skipPlist
        self.noResign = noResign
        self.json = json
        self.dryRun = dryRun
    }
}

/// Parse errors, reported on stderr with exit code 2.
public enum ParseError: Error, Sendable, Equatable {
    case unknownSubcommand(String)
    case missingValue(String)
    case invalidValue(flag: String, value: String)
}

public enum CLI: Sendable {
    public static let version = "0.1.0"
    public static let defaultSpotifyAppPath = "/Applications/Spotify.app"
    public static let bundleID = "com.spotify.client"

    public static let helpText: String = """
        headless-spotify \(version) — hide official Spotify from Dock + Cmd-Tab

        USAGE:
          headless-spotify [--spotify-app <path>] [--timeout <s>] <status|hide|restore|watch>
          headless-spotify --help | --version

        SUBCOMMANDS:
          status    Report Dock presence, LSUIElement, `player state` (exit 0 only
                    when headless + running + scriptable)
          hide      Set LSUIElement=true, re-sign ad-hoc, relaunch headless
                    (activates:false), verify `player state` within --timeout
          restore   Restore the Info.plist backup (original Apple signature
                    returns), relaunch normally
          watch     Persistence daemon: re-apply hiding when Spotify updates or
                    the Dock icon returns (task 3)

        OPTIONS:
          --spotify-app <path>  Path to Spotify.app (default: \(defaultSpotifyAppPath))
          --timeout <seconds>   AppleScript wait after relaunch (default: 10)
          --skip-relaunch       Edit plist only, do not relaunch (for install.sh)
          --skip-plist          Relaunch + verify only, do not edit plist
          --no-resign           Skip ad-hoc re-sign (relaunch may fail)
          --json                Machine-readable `status` output
          --dry-run             Print the plan without changing anything
          -h, --help            Show this help
          -v, --version         Show version

        CONTRACT (shared with Sonar):
          Process stays com.spotify.client; AppleScript ("tell application \\"Spotify\\"") keeps working.
          `hide` needs write access to Spotify.app — otherwise run `sudo ./install.sh`.
        """

    /// Parse argv (including argv[0]). Never exits; callers map errors to stderr + code 2.
    public static func parse(_ argv: [String]) -> Result<Invocation, ParseError> {
        var invocation = Invocation()
        let args = Array(argv.dropFirst())
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-h", "--help":
                invocation.showHelp = true
            case "-v", "--version":
                invocation.showVersion = true
            case "--spotify-app":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                invocation.spotifyAppPath = args[i + 1]
                i += 1
            case "--timeout":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                guard let seconds = TimeInterval(args[i + 1]), seconds > 0 else {
                    return .failure(.invalidValue(flag: arg, value: args[i + 1]))
                }
                invocation.timeout = seconds
                i += 1
            case "--skip-relaunch":
                invocation.skipRelaunch = true
            case "--skip-plist":
                invocation.skipPlist = true
            case "--no-resign":
                invocation.noResign = true
            case "--json":
                invocation.json = true
            case "--dry-run":
                invocation.dryRun = true
            default:
                if arg.hasPrefix("--spotify-app=") {
                    invocation.spotifyAppPath = String(arg.dropFirst("--spotify-app=".count))
                } else if arg.hasPrefix("--timeout=") {
                    let value = String(arg.dropFirst("--timeout=".count))
                    guard let seconds = TimeInterval(value), seconds > 0 else {
                        return .failure(.invalidValue(flag: "--timeout", value: value))
                    }
                    invocation.timeout = seconds
                } else if arg.hasPrefix("-") {
                    return .failure(.unknownSubcommand(arg))
                } else if let sub = Subcommand(rawValue: arg) {
                    invocation.subcommand = sub
                } else {
                    return .failure(.unknownSubcommand(arg))
                }
            }
            i += 1
        }
        if argv.count <= 1 {
            invocation.showHelp = true
        }
        return .success(invocation)
    }
}
