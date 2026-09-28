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
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>watch</string>
                <string>--interval</string>
                <string>\(Int(interval))</string>
                <string>--spotify-app</string>
                <string>\(spotifyAppPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>30</integer>
            <key>WatchPaths</key>
            <array>
                <string>\(spotifyAppPath)/Contents/Info.plist</string>
            </array>
            <key>StandardOutPath</key>
            <string>/tmp/headless-spotify-watcher.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/headless-spotify-watcher.log</string>
        </dict>
        </plist>

        """
    }
}
