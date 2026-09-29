// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// LaunchAgent definition (single source of truth): the CLI prints it
// (`watch --print-agent-plist`) and install.sh installs exactly that output,
// so the checked-in file and the installed agent can never drift.

import Foundation

public enum AgentPlist: Sendable {
    public static let label = "com.headless-spotify.watcher"

    public static func agentPlistPath(homeDirectory: String) -> String {
        homeDirectory + "/Library/LaunchAgents/\(label).plist"
    }

    /// KeepAlive daemon running `watch`; WatchPaths re-fires right after a
    /// Spotify self-update rewrites Info.plist.
    public static func contents(binaryPath: String, spotifyAppPath: String, interval: TimeInterval) -> String {
        // A path containing & or < would otherwise produce a plist that
        // LaunchServices refuses to parse, taking the watcher with it.
        let binary = escape(binaryPath)
        let app = escape(spotifyAppPath)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binary)</string>
                <string>watch</string>
                <string>--interval</string>
                <string>\(Int(interval))</string>
                <string>--spotify-app</string>
                <string>\(app)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>30</integer>
            <key>WatchPaths</key>
            <array>
                <string>\(app)/Contents/Info.plist</string>
            </array>
            <key>StandardOutPath</key>
            <string>/tmp/headless-spotify-watcher.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/headless-spotify-watcher.log</string>
        </dict>
        </plist>

        """
    }

    /// Escape the five XML entities so any path yields a parseable plist.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
