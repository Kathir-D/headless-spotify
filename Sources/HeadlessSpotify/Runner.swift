// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Command orchestration: status / hide / restore (task 2) + watch stub (task 3).
//
// Exit codes: 0 = done and headless+scriptable (or help/version/dry-run),
// 1 = operational failure or "not headless", 2 = usage error / app missing.

import Foundation

public enum Runner {
    public static func run(
        _ invocation: Invocation,
        output: @Sendable (String) -> Void = { print($0) },
        errorOutput: @Sendable (String) -> Void = { fputs($0 + "\n", stderr) }
    ) async -> Int32 {
        if invocation.showHelp || invocation.subcommand == nil {
            output(CLI.helpText)
            return 0
        }
        if invocation.showVersion {
            output("headless-spotify \(CLI.version)")
            return 0
        }
        switch invocation.subcommand {
        case .status:
            return await status(invocation, output: output, errorOutput: errorOutput)
        case .hide:
            return await hide(invocation, output: output, errorOutput: errorOutput)
        case .restore:
            return await restore(invocation, output: output, errorOutput: errorOutput)
        case .watch:
            output("watch: persistence daemon lands in task 3 (injector fallback + LaunchAgent watcher).")
            return 0
        case .none:
            output(CLI.helpText)
            return 0
        }
    }

    // MARK: - status

    public struct StatusReport: Sendable, Equatable {
        public var appPath: String
        public var installed: Bool
        public var running: Bool
        public var lsuiElement: Bool?
        public var dock: DockPresence
        public var playerState: String?
        public var hasBackup: Bool

        public var isHeadless: Bool { lsuiElement == true || dock == .hidden }
        public var isScriptable: Bool { playerState != nil }
        public var isReady: Bool { installed && running && isHeadless && isScriptable }
    }

    public static func collectStatus(
        appPath: String,
        run: SpotifyScripting.Runner = ProcessRunner.run
    ) async -> StatusReport {
        let plist = SpotifyPlist(appPath: appPath)
        let installed = plist.appExists && plist.plistExists
        let lsui: Bool? = installed ? (try? plist.readLSUIElement()) : nil
        let running = SpotifyScripting.isSpotifyRunning(run: run)
        let dock = await SpotifyState.dockPresence()
        let player = running ? SpotifyScripting.playerState(run: run) : nil
        return StatusReport(
            appPath: appPath,
            installed: installed,
            running: running,
            lsuiElement: lsui,
            dock: dock,
            playerState: player,
            hasBackup: plist.hasBackup
        )
    }

    static func status(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) async -> Int32 {
        let report = await collectStatus(appPath: inv.spotifyAppPath)
        if inv.json {
            output(jsonStatus(report))
        } else {
            output(textStatus(report))
        }
        return report.isReady ? 0 : 1
    }

    static func textStatus(_ r: StatusReport) -> String {
        var lines: [String] = []
        lines.append("Spotify: \(r.appPath) (\(CLI.bundleID))")
        lines.append("Installed: \(r.installed ? "yes" : "no")")
        let lsui = r.lsuiElement.map { $0 ? "true (headless)" : "false (normal)" } ?? "absent (normal)"
        lines.append("LSUIElement: \(lsui)")
        switch r.dock {
        case .visible: lines.append("Dock: visible (regular)")
        case .hidden: lines.append("Dock: hidden (accessory)")
        case .prohibited: lines.append("Dock: prohibited (unexpected)")
        case .notRunning: lines.append("Dock: n/a (not running)")
        }
        lines.append("Player state: \(r.playerState ?? (r.running ? "not answering" : "n/a (not running)"))")
        lines.append("Backup: \(r.hasBackup ? "present" : "absent")")
        lines.append("Headless: \(r.isHeadless ? "yes" : "no") — scriptable: \(r.isScriptable ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    static func jsonStatus(_ r: StatusReport) -> String {
        let dict: [String: Any] = [
            "app": r.appPath,
            "bundle": CLI.bundleID,
            "installed": r.installed,
            "running": r.running,
            "lsui_element": r.lsuiElement as Any,
            "dock": r.dock.rawValue,
            "headless": r.isHeadless,
            "player_state": r.playerState as Any,
            "scriptable": r.isScriptable,
            "backup_present": r.hasBackup,
            "ready": r.isReady,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "{}"
    }

    // MARK: - hide

    static func hidePlan(_ inv: Invocation, lsui: Bool?, writable: Bool) -> String {
        var lines = ["hide plan for \(inv.spotifyAppPath):"]
        if inv.skipPlist {
            lines.append("  - skip plist edit (--skip-plist)")
        } else {
            lines.append("  - back up Info.plist (+ CodeResources seal)")
            lines.append("  - set LSUIElement=true (currently: \(lsui.map(String.init) ?? "absent"))")
            lines.append(inv.noResign ? "  - skip ad-hoc re-sign (--no-resign)" : "  - ad-hoc re-sign (original signature restored by `restore`)")
        }
        if inv.skipRelaunch {
            lines.append("  - skip relaunch (--skip-relaunch)")
        } else {
            lines.append("  - quit Spotify if running, relaunch headless (activates:false)")
            lines.append("  - poll `player state` up to \(Int(inv.timeout))s, verify Dock hidden")
        }
        lines.append("  - writable: \(writable ? "yes" : "no — run `sudo ./install.sh`")")
        return lines.joined(separator: "\n")
    }

    static func hide(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) async -> Int32 {
        let plist = SpotifyPlist(appPath: inv.spotifyAppPath)
        guard plist.appExists else {
            errorOutput("hide: Spotify not found at \(inv.spotifyAppPath)")
            return 2
        }
        let current = try? plist.readLSUIElement()
        if inv.dryRun {
            output(hidePlan(inv, lsui: current, writable: plist.isWritable))
            return 0
        }
        if !inv.skipPlist {
            guard plist.isWritable else {
                errorOutput("hide: \(plist.infoPlistURL.path) is not writable — run `sudo ./install.sh \(inv.spotifyAppPath)`")
                return 1
            }
            do {
                try plist.backup()
                try plist.setLSUIElement(true, backupFirst: false)
                output("hide: LSUIElement=true (backup kept)")
            } catch {
                errorOutput("hide: plist edit failed: \(error)")
                return 1
            }
            if !inv.noResign {
                output("hide: ad-hoc re-signing (required on Apple Silicon; `restore` brings the original signature back)…")
                let result = SpotifyScripting.resignAdHoc(appPath: inv.spotifyAppPath)
                if result.exitCode != 0 {
                    errorOutput("hide: re-sign failed (continuing anyway): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        if !inv.skipRelaunch {
            let wasRunning = await SpotifyState.runningApp() != nil
            if wasRunning {
                output("hide: quitting Spotify…")
                _ = await SpotifyState.terminate()
            }
            do {
                _ = try await SpotifyState.launchHeadless(appPath: inv.spotifyAppPath)
            } catch {
                errorOutput("hide: relaunch failed: \(error)")
                return 1
            }
            output("hide: waiting for AppleScript (≤\(Int(inv.timeout))s)…")
            guard let state = SpotifyScripting.waitForScripting(timeout: inv.timeout) else {
                errorOutput("hide: Spotify did not answer AppleScript within \(Int(inv.timeout))s")
                return 1
            }
            let presence = await SpotifyState.dockPresence()
            output("hide: ready — player state: \(state), Dock: \(presence.rawValue)")
            return presence == .hidden ? 0 : 1
        }
        output("hide: plist updated (relaunch skipped)")
        return 0
    }

    // MARK: - restore

    static func restore(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) async -> Int32 {
        let plist = SpotifyPlist(appPath: inv.spotifyAppPath)
        guard plist.appExists else {
            errorOutput("restore: Spotify not found at \(inv.spotifyAppPath)")
            return 2
        }
        if inv.dryRun {
            output("restore plan for \(inv.spotifyAppPath): restore Info.plist backup (\(plist.hasBackup ? "present" : "absent")), relaunch normally, verify Dock visible.")
            return 0
        }
        if !inv.skipPlist {
            guard plist.isWritable else {
                errorOutput("restore: \(plist.infoPlistURL.path) is not writable — run `sudo ./uninstall.sh \(inv.spotifyAppPath)`")
                return 1
            }
            do {
                if plist.hasBackup {
                    try plist.restore()
                    output("restore: original Info.plist (+ seal) restored, backup removed")
                } else if (try? plist.readLSUIElement()) == true {
                    try plist.setLSUIElement(nil, backupFirst: true)
                    output("restore: no backup found — removed LSUIElement key (a backup of the edited plist was kept)")
                } else {
                    output("restore: already in normal mode (LSUIElement absent)")
                }
            } catch {
                errorOutput("restore: plist restore failed: \(error)")
                return 1
            }
            // Never ad-hoc resign here: restoring the original files brings
            // back Apple's own signature. Verify and report.
            let verify = SpotifyScripting.verifySignature(appPath: inv.spotifyAppPath)
            if verify.exitCode == 0 {
                output("restore: code signature verifies (original Apple signature)")
            } else {
                errorOutput("restore: WARNING — signature does not verify; reinstall Spotify if it refuses to launch.")
            }
        }
        if !inv.skipRelaunch {
            if await SpotifyState.runningApp() != nil {
                output("restore: quitting Spotify…")
                _ = await SpotifyState.terminate()
            }
            do {
                _ = try await SpotifyState.launchNormal(appPath: inv.spotifyAppPath)
            } catch {
                errorOutput("restore: relaunch failed: \(error)")
                return 1
            }
            let state = SpotifyScripting.waitForScripting(timeout: inv.timeout) ?? "unknown"
            let presence = await SpotifyState.dockPresence()
            output("restore: done — player state: \(state), Dock: \(presence.rawValue)")
            return presence == .visible ? 0 : 1
        }
        output("restore: plist restored (relaunch skipped)")
        return 0
    }
}
