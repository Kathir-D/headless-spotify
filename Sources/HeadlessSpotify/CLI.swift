// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// CLI argument model for headless-spotify.
// Dependency-free (stdlib + Foundation only) so the MIT-only rule stays trivial.

import Foundation

/// Subcommands stubbed in task 1; real behavior lands in tasks 2 (hide/restore
/// via LSUIElement) and 3 (injector fallback + watcher).
public enum Subcommand: String, Sendable, CaseIterable {
    case status
    case hide
    case restore
}

/// Parsed CLI invocation.
public struct Invocation: Sendable, Equatable {
    public var subcommand: Subcommand?
    public var showHelp: Bool
    public var spotifyAppPath: String

    public init(
        subcommand: Subcommand? = nil,
        showHelp: Bool = false,
        spotifyAppPath: String = CLI.defaultSpotifyAppPath
    ) {
        self.subcommand = subcommand
        self.showHelp = showHelp
        self.spotifyAppPath = spotifyAppPath
    }
}

/// Parse errors, reported on stderr with exit code 2.
public enum ParseError: Error, Sendable, Equatable {
    case unknownSubcommand(String)
}

public enum CLI: Sendable {
    public static let version = "0.1.0"
    public static let defaultSpotifyAppPath = "/Applications/Spotify.app"
    public static let bundleID = "com.spotify.client"

    public static let helpText: String = """
        headless-spotify \(version) — hide official Spotify from Dock + Cmd-Tab

        USAGE:
          headless-spotify [--spotify-app <path>] <status|hide|restore>
          headless-spotify --help

        SUBCOMMANDS (task 1 stubs; behavior lands in tasks 2–3):
          status    Report whether Spotify is running headless
          hide      Hide Spotify (LSUIElement, injector fallback later)
          restore   Restore Spotify Dock icon

        OPTIONS:
          --spotify-app <path>  Path to Spotify.app (default: \(defaultSpotifyAppPath))
          -h, --help            Show this help
          -v, --version         Show version

        CONTRACT:
          Process stays com.spotify.client; AppleScript ("tell application \\"Spotify\\"") keeps working.
        """

    /// Parse argv (including argv[0]). Never exits; callers map errors to stderr + code 2.
    public static func parse(_ argv: [String]) -> Result<Invocation, ParseError> {
        var invocation = Invocation()
        let args = argv.dropFirst()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "-h", "--help":
                invocation.showHelp = true
            case "-v", "--version":
                invocation.showHelp = true
            case "--spotify-app":
                if let value = iterator.next() {
                    invocation.spotifyAppPath = value
                }
            case let flag where flag.hasPrefix("--spotify-app="):
                invocation.spotifyAppPath = String(flag.dropFirst("--spotify-app=".count))
            default:
                if let sub = Subcommand(rawValue: arg) {
                    invocation.subcommand = sub
                } else {
                    return .failure(.unknownSubcommand(arg))
                }
            }
        }
        if argv.count <= 1 {
            invocation.showHelp = true
        }
        return .success(invocation)
    }

    /// Run stub subcommands. Returns process exit code.
    /// - Parameters:
    ///   - invocation: parsed invocation
    ///   - output: line printer for stdout (injectable for tests)
    public static func run(
        _ invocation: Invocation,
        output: (String) -> Void = { print($0) }
    ) -> Int32 {
        if invocation.showHelp || invocation.subcommand == nil {
            output(helpText)
            return 0
        }
        switch invocation.subcommand {
        case .status:
            // Task 2 will check Dock absence + `player state` scriptability.
            output("status: stub — LSUIElement mode + scriptability check land in task 2")
            return 0
        case .hide:
            // Task 2 (LSUIElement) / task 3 (injector fallback).
            output("hide: stub — LSUIElement hide lands in task 2 (\(invocation.spotifyAppPath))")
            return 0
        case .restore:
            output("restore: stub — plist restore lands in task 2 (\(invocation.spotifyAppPath))")
            return 0
        case .none:
            output(helpText)
            return 0
        }
    }
}
