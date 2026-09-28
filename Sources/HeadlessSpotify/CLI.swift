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
    case control
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
    /// `hide`: plist (default primary), injector, or auto (plist → injector fallback).
    public var mode: HideMode
    /// Explicit injector dylib path (else $HEADLESS_INJECTOR_DYLIB, install dir, CLI neighbor).
    public var injectorPath: String?
    /// `watch`: seconds between passes (default 15).
    public var interval: TimeInterval
    /// `watch`: run N passes then exit (0 = forever; for debugging/tests).
    public var iterations: Int
    /// `watch --install-agent/--uninstall-agent`: manage the LaunchAgent.
    public var installAgent: Bool
    public var uninstallAgent: Bool
    /// `watch --print-agent-plist`: print the agent plist to stdout.
    public var printAgentPlist: Bool
    /// `control`: media action + optional numeric value (set-volume).
    public var controlAction: ControlAction?
    public var controlValue: Int?

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
        dryRun: Bool = false,
        mode: HideMode = .auto,
        injectorPath: String? = nil,
        interval: TimeInterval = 15,
        iterations: Int = 0,
        installAgent: Bool = false,
        uninstallAgent: Bool = false,
        printAgentPlist: Bool = false,
        controlAction: ControlAction? = nil,
        controlValue: Int? = nil
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
        self.mode = mode
        self.injectorPath = injectorPath
        self.interval = interval
        self.iterations = iterations
        self.installAgent = installAgent
        self.uninstallAgent = uninstallAgent
        self.printAgentPlist = printAgentPlist
        self.controlAction = controlAction
        self.controlValue = controlValue
    }
}

/// Parse errors, reported on stderr with exit code 2.
public enum ParseError: Error, Sendable, Equatable {
    case unknownSubcommand(String)
    case missingValue(String)
    case invalidValue(flag: String, value: String)
}

public enum CLI: Sendable {
    public static let version = "0.1.0-beta.1"
    public static let defaultSpotifyAppPath = "/Applications/Spotify.app"
    public static let bundleID = "com.spotify.client"

    public static let helpText: String = """
        headless-spotify \(version) — hide official Spotify from Dock + Cmd-Tab

        USAGE:
          headless-spotify [--spotify-app <path>] [--timeout <s>] <status|hide|restore|watch>
          headless-spotify control <play|pause|toggle|next|previous|volume|set-volume N|volume-up|volume-down>
          headless-spotify --help | --version

        SUBCOMMANDS:
          status    Report Dock presence, LSUIElement, `player state` (exit 0 only
                    when headless + running + scriptable)
          hide      Set LSUIElement=true, re-sign ad-hoc, relaunch headless
                    (activates:false), verify `player state` within --timeout.
                    --mode injector (or auto fallback) uses the accessory-policy
                    dylib when the Dock icon survives.
          restore   Restore the Info.plist backup (original Apple signature
                    returns), relaunch normally
          watch     Persistence daemon: re-apply hiding when Spotify updates or
                    the Dock icon returns; --install-agent wires the LaunchAgent
          control   Media passthrough (same AppleScript Sonar uses): play,
                    pause, toggle, next, previous, volume, set-volume,
                    volume-up, volume-down. Never launches Spotify.

        OPTIONS:
          --spotify-app <path>  Path to Spotify.app (default: \(defaultSpotifyAppPath))
          --timeout <seconds>   AppleScript wait after relaunch (default: 10)
          --mode <auto|plist|injector>
                                Hiding strategy for `hide` (default: auto)
          --injector <path>     Injector dylib path (default: install dir)
          --skip-relaunch       Edit plist only, do not relaunch (for install.sh)
          --skip-plist          Relaunch + verify only, do not edit plist
          --no-resign           Skip ad-hoc re-sign (relaunch may fail)
          --interval <seconds>  `watch` pass interval (default: 15)
          --iterations <n>      `watch` passes then exit, 0 = forever (default: 0)
          --install-agent       Install + bootstrap the watcher LaunchAgent
          --uninstall-agent     Bootout + remove the watcher LaunchAgent
          --print-agent-plist   Print the LaunchAgent plist to stdout
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
            case "--mode":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                guard let mode = HideMode(rawValue: args[i + 1]) else {
                    return .failure(.invalidValue(flag: arg, value: args[i + 1]))
                }
                invocation.mode = mode
                i += 1
            case "--injector":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                invocation.injectorPath = args[i + 1]
                i += 1
            case "--interval":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                guard let seconds = TimeInterval(args[i + 1]), seconds > 0 else {
                    return .failure(.invalidValue(flag: arg, value: args[i + 1]))
                }
                invocation.interval = seconds
                i += 1
            case "--iterations":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                guard let n = Int(args[i + 1]), n >= 0 else {
                    return .failure(.invalidValue(flag: arg, value: args[i + 1]))
                }
                invocation.iterations = n
                i += 1
            case "--skip-relaunch":
                invocation.skipRelaunch = true
            case "--install-agent":
                invocation.installAgent = true
            case "--uninstall-agent":
                invocation.uninstallAgent = true
            case "--print-agent-plist":
                invocation.printAgentPlist = true
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
                } else if arg.hasPrefix("--mode=") {
                    let value = String(arg.dropFirst("--mode=".count))
                    guard let mode = HideMode(rawValue: value) else {
                        return .failure(.invalidValue(flag: "--mode", value: value))
                    }
                    invocation.mode = mode
                } else if arg.hasPrefix("--injector=") {
                    invocation.injectorPath = String(arg.dropFirst("--injector=".count))
                } else if arg.hasPrefix("--timeout=") {
                    let value = String(arg.dropFirst("--timeout=".count))
                    guard let seconds = TimeInterval(value), seconds > 0 else {
                        return .failure(.invalidValue(flag: "--timeout", value: value))
                    }
                    invocation.timeout = seconds
                } else if arg.hasPrefix("--interval=") {
                    let value = String(arg.dropFirst("--interval=".count))
                    guard let seconds = TimeInterval(value), seconds > 0 else {
                        return .failure(.invalidValue(flag: "--interval", value: value))
                    }
                    invocation.interval = seconds
                } else if arg.hasPrefix("--iterations=") {
                    let value = String(arg.dropFirst("--iterations=".count))
                    guard let n = Int(value), n >= 0 else {
                        return .failure(.invalidValue(flag: "--iterations", value: value))
                    }
                    invocation.iterations = n
                } else if arg.hasPrefix("-") {
                    return .failure(.unknownSubcommand(arg))
                } else if let sub = Subcommand(rawValue: arg) {
                    invocation.subcommand = sub
                } else if invocation.subcommand == .control,
                          invocation.controlAction == nil,
                          let action = ControlAction(rawValue: arg)
                {
                    invocation.controlAction = action
                } else if invocation.subcommand == .control,
                          invocation.controlValue == nil,
                          let n = Int(arg)
                {
                    invocation.controlValue = n
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
