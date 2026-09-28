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
        if invocation.showVersion {
            output("headless-spotify \(CLI.version)")
            return 0
        }
        if invocation.showHelp || invocation.subcommand == nil {
            output(CLI.helpText)
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
            return await watch(invocation, output: output, errorOutput: errorOutput)
        case .control:
            return control(invocation, output: output, errorOutput: errorOutput)
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
            lines.append("  - quit Spotify if running, relaunch headless (activates:false, mode: \(inv.mode.rawValue))")
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
            switch inv.mode {
            case .plist:
                return await relaunchAndVerify(inv, output: output, errorOutput: errorOutput, useInjector: nil)
            case .injector:
                guard let dylib = Injector.locate(explicit: inv.injectorPath, cliBinaryPath: CommandLine.arguments.first) else {
                    errorOutput("hide: injector dylib not found — pass --injector <path> or install it (sudo ./install.sh)")
                    return 1
                }
                warnIfHardened(appPath: inv.spotifyAppPath, output: output)
                return await relaunchAndVerify(inv, output: output, errorOutput: errorOutput, useInjector: dylib)
            case .auto:
                let code = await relaunchAndVerify(inv, output: output, errorOutput: errorOutput, useInjector: nil)
                if code == 0 { return 0 }
                // Plist mode verified but Dock survived (or verify failed) → fallback.
                guard let dylib = Injector.locate(explicit: inv.injectorPath, cliBinaryPath: CommandLine.arguments.first) else {
                    errorOutput("hide: plist mode did not hide the Dock and no injector dylib is installed.")
                    return code
                }
                output("hide: plist mode insufficient — falling back to injector (\(dylib))…")
                warnIfHardened(appPath: inv.spotifyAppPath, output: output)
                _ = await SpotifyState.terminate()
                return await relaunchAndVerify(inv, output: output, errorOutput: errorOutput, useInjector: dylib)
            }
        }
        output("hide: plist updated (relaunch skipped)")
        return 0
    }

    static func warnIfHardened(appPath: String, output: @Sendable (String) -> Void) {
        if Injector.isHardenedRuntime(appPath: appPath) {
            output("hide: note — Spotify is hardened-runtime, which strips DYLD_* vars; the injector is likely ignored and plist mode stays primary.")
        }
    }

    /// Relaunch (plain or injector) then poll AppleScript + Dock state.
    /// Returns 0 only when the Dock is hidden and Spotify answers scripting.
    static func relaunchAndVerify(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void,
        useInjector dylib: String?
    ) async -> Int32 {
        do {
            if let dylib {
                _ = try await SpotifyState.launchWithInjector(appPath: inv.spotifyAppPath, dylibPath: dylib)
            } else {
                _ = try await SpotifyState.launchHeadless(appPath: inv.spotifyAppPath)
            }
        } catch {
            errorOutput("hide: relaunch failed: \(error)")
            return 1
        }
        output("hide: waiting for AppleScript (≤\(Int(inv.timeout))s)…")
        guard let state = SpotifyScripting.waitForScripting(timeout: inv.timeout) else {
            errorOutput("hide: Spotify did not answer AppleScript within \(Int(inv.timeout))s")
            errorOutput("hide: hiding failed — run `headless-spotify restore --spotify-app \(inv.spotifyAppPath)` to return Spotify to normal.")
            errorOutput("hide: note — Spotify ≥1.3.1 exits on launch when LSUIElement=true is present (verified 2026-09-28); plist mode is blocked on current Spotify.")
            return 1
        }
        let presence = await SpotifyState.dockPresence()
        output("hide: ready — player state: \(state), Dock: \(presence.rawValue)")
        if presence != .hidden {
            errorOutput("hide: Dock still visible — run `headless-spotify restore --spotify-app \(inv.spotifyAppPath)` to return Spotify to normal.")
        }
        return presence == .hidden ? 0 : 1
    }

    // MARK: - control (media passthrough)

    /// Synchronous: no AppKit, only bounded osascript calls.
    static func control(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void,
        run: SpotifyScripting.Runner = ProcessRunner.run
    ) -> Int32 {
        guard let action = inv.controlAction else {
            errorOutput("control: missing action — try 'headless-spotify control play|pause|toggle|next|previous|volume|set-volume N|volume-up|volume-down'.")
            return 2
        }
        if inv.dryRun {
            output("control plan: \(action.rawValue)\(inv.controlValue.map { " \($0)" } ?? "") via AppleScript (no Spotify launch).")
            return 0
        }
        let (code, line) = Control.perform(action, value: inv.controlValue, run: run)
        (code == 0 ? output : errorOutput)(line)
        return code
    }

    // MARK: - watch (persistence daemon)

    static func watch(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) async -> Int32 {
        if inv.printAgentPlist {
            let binary = CommandLine.arguments.first ?? "/usr/local/bin/headless-spotify"
            output(AgentPlist.contents(binaryPath: binary, spotifyAppPath: inv.spotifyAppPath, interval: inv.interval))
            return 0
        }
        if inv.installAgent {
            return installAgent(inv, output: output, errorOutput: errorOutput)
        }
        if inv.uninstallAgent {
            return uninstallAgent(output: output, errorOutput: errorOutput)
        }
        if inv.dryRun {
            output("watch plan for \(inv.spotifyAppPath): every \(Int(inv.interval))s check Dock + LSUIElement + app version; re-apply hiding on drift.")
            return 0
        }
        let plist = SpotifyPlist(appPath: inv.spotifyAppPath)
        guard plist.appExists else {
            errorOutput("watch: Spotify not found at \(inv.spotifyAppPath)")
            return 2
        }
        output("watch: guarding \(inv.spotifyAppPath) every \(Int(inv.interval))s (Ctrl-C / SIGTERM to stop)")
        var lastVersion = plist.appVersion()
        var plistFailures = 0
        var consecutiveFailures = 0
        var pass = 0
        while true {
            pass += 1
            let report = await collectStatus(appPath: inv.spotifyAppPath)
            let currentVersion = plist.appVersion()
            let action = Watcher.decide(
                report: report,
                lastSeenVersion: lastVersion,
                currentVersion: currentVersion,
                plistFailures: plistFailures
            )
            let outcome: Int32
            switch action {
            case .none:
                plistFailures = 0
                outcome = 0
            case .relaunchHeadless(let reason):
                output("watch: \(reason) — re-applying…")
                outcome = await reapply(
                    Invocation(subcommand: .hide, spotifyAppPath: inv.spotifyAppPath, timeout: inv.timeout, mode: .auto),
                    output: output,
                    errorOutput: errorOutput
                )
                plistFailures = outcome == 0 ? 0 : plistFailures + 1
            case .reapplyPlist(let reason):
                output("watch: \(reason) — re-applying…")
                outcome = await reapply(
                    Invocation(subcommand: .hide, spotifyAppPath: inv.spotifyAppPath, timeout: inv.timeout, mode: .auto),
                    output: output,
                    errorOutput: errorOutput
                )
                plistFailures = outcome == 0 ? 0 : plistFailures
            case .injectorFallback(let reason):
                output("watch: \(reason) — trying injector…")
                _ = await reapply(
                    Invocation(subcommand: .hide, spotifyAppPath: inv.spotifyAppPath, timeout: inv.timeout, mode: .injector),
                    output: output,
                    errorOutput: errorOutput
                )
                outcome = 0
                plistFailures = 0
            }
            consecutiveFailures = outcome == 0 ? 0 : consecutiveFailures + 1
            let sleep = Watcher.backoffInterval(base: inv.interval, failures: consecutiveFailures)
            if outcome != 0, consecutiveFailures == 1 {
                errorOutput("watch: hiding failed — backing off to \(Int(sleep))s between attempts (up to \(Int(Watcher.backoffInterval(base: inv.interval, failures: 4)))s). If this persists, see README 'Current status'.")
            }
            lastVersion = currentVersion
            if inv.iterations > 0, pass >= inv.iterations {
                return 0
            }
            try? await Task.sleep(nanoseconds: UInt64(sleep * 1_000_000_000))
        }
    }

    /// hide without the pre-quit duplication: shared by hide/watch.
    static func reapply(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) async -> Int32 {
        await hide(inv, output: output, errorOutput: errorOutput)
    }

    // MARK: - LaunchAgent management (persistence across login/updates)

    static func installAgent(
        _ inv: Invocation,
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) -> Int32 {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let dest = AgentPlist.agentPlistPath(homeDirectory: home)
        let binary = CommandLine.arguments.first ?? "/usr/local/bin/headless-spotify"
        let contents = AgentPlist.contents(binaryPath: binary, spotifyAppPath: inv.spotifyAppPath, interval: inv.interval)
        do {
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: dest).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )
            try contents.write(toFile: dest, atomically: true, encoding: .utf8)
        } catch {
            errorOutput("watch: writing agent plist failed: \(error)")
            return 1
        }
        let domain = "gui/\(getuid())"
        let boot = ProcessRunner.run("/bin/launchctl", ["bootout", domain, dest])
        _ = boot // ignore: not loaded yet is fine
        let load = ProcessRunner.run("/bin/launchctl", ["bootstrap", domain, dest])
        if load.exitCode != 0 {
            errorOutput("watch: bootstrap failed: \(load.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return 1
        }
        output("watch: agent installed + loaded: \(dest)")
        return 0
    }

    static func uninstallAgent(
        output: @Sendable (String) -> Void,
        errorOutput: @Sendable (String) -> Void
    ) -> Int32 {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let dest = AgentPlist.agentPlistPath(homeDirectory: home)
        let domain = "gui/\(getuid())"
        _ = ProcessRunner.run("/bin/launchctl", ["bootout", domain, dest])
        if FileManager.default.fileExists(atPath: dest) {
            do {
                try FileManager.default.removeItem(atPath: dest)
            } catch {
                errorOutput("watch: removing agent plist failed: \(error)")
                return 1
            }
        }
        output("watch: agent removed: \(dest)")
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
