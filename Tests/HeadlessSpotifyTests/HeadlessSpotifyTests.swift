import Foundation
import Testing

@testable import HeadlessSpotify

@Suite("CLI parsing")
struct CLIParseTests {
    @Test("bare invocation shows help")
    func bareShowsHelp() throws {
        let result = CLI.parse(["headless-spotify"])
        #expect(try result.get().showHelp == true)
    }

    @Test("--help / -h flag")
    func helpFlag() throws {
        for flag in ["-h", "--help"] {
            let result = CLI.parse(["headless-spotify", flag])
            #expect(try result.get().showHelp == true)
        }
    }

    @Test("--version / -v flag")
    func versionFlag() throws {
        for flag in ["-v", "--version"] {
            let result = CLI.parse(["headless-spotify", flag])
            #expect(try result.get().showVersion == true)
        }
    }

    @Test("subcommands parse", arguments: ["status", "hide", "restore", "watch", "control"])
    func subcommandsParse(name: String) throws {
        let result = CLI.parse(["headless-spotify", name])
        #expect(try result.get().subcommand == Subcommand(rawValue: name))
    }

    @Test("unknown subcommand errors")
    func unknownErrors() {
        let result = CLI.parse(["headless-spotify", "cloak"])
        #expect(result == .failure(.unknownSubcommand("cloak")))
    }

    @Test("unknown flag errors")
    func unknownFlagErrors() {
        let result = CLI.parse(["headless-spotify", "--cloak"])
        #expect(result == .failure(.unknownSubcommand("--cloak")))
    }

    @Test("--spotify-app override")
    func appPathOverride() throws {
        let custom = "/Volumes/Music/Spotify.app"
        let r1 = CLI.parse(["headless-spotify", "--spotify-app", custom, "status"])
        #expect(try r1.get().spotifyAppPath == custom)
        let r2 = CLI.parse(["headless-spotify", "--spotify-app=\(custom)", "hide"])
        #expect(try r2.get().spotifyAppPath == custom)
    }

    @Test("missing --spotify-app value errors")
    func missingValueErrors() {
        #expect(CLI.parse(["headless-spotify", "hide", "--spotify-app"]) == .failure(.missingValue("--spotify-app")))
    }

    @Test("--timeout parses")
    func timeoutParses() throws {
        let ok = try CLI.parse(["headless-spotify", "--timeout", "5", "hide"]).get()
        #expect(ok.timeout == 5)
        let eq = try CLI.parse(["headless-spotify", "--timeout=7", "hide"]).get()
        #expect(eq.timeout == 7)
        #expect(CLI.parse(["headless-spotify", "--timeout", "soon", "hide"]) == .failure(.invalidValue(flag: "--timeout", value: "soon")))
        #expect(CLI.parse(["headless-spotify", "--timeout", "-3", "hide"]) == .failure(.invalidValue(flag: "--timeout", value: "-3")))
    }

    @Test("installer split flags parse")
    func splitFlagsParse() throws {
        let inv = try CLI.parse(["headless-spotify", "hide", "--skip-relaunch", "--skip-plist", "--no-resign", "--json", "--dry-run"]).get()
        #expect(inv.skipRelaunch && inv.skipPlist && inv.noResign && inv.json && inv.dryRun)
    }

    @Test("task 3 flags parse")
    func task3FlagsParse() throws {
        let inv = try CLI.parse([
            "headless-spotify", "hide", "--mode=injector", "--injector=/tmp/x.dylib",
        ]).get()
        #expect(inv.mode == .injector)
        #expect(inv.injectorPath == "/tmp/x.dylib")
        let bad = CLI.parse(["headless-spotify", "hide", "--mode", "cloak"])
        #expect(bad == .failure(.invalidValue(flag: "--mode", value: "cloak")))
        let watch = try CLI.parse([
            "headless-spotify", "watch", "--interval", "30", "--iterations=2",
            "--install-agent", "--uninstall-agent", "--print-agent-plist",
        ]).get()
        #expect(watch.interval == 30 && watch.iterations == 2)
        #expect(watch.installAgent && watch.uninstallAgent && watch.printAgentPlist)
    }

    @Test("control action + value parse")
    func controlParse() throws {
        let inv = try CLI.parse(["headless-spotify", "control", "set-volume", "42"]).get()
        #expect(inv.subcommand == .control)
        #expect(inv.controlAction == .setVolume)
        #expect(inv.controlValue == 42)
        let toggle = try CLI.parse(["headless-spotify", "control", "toggle"]).get()
        #expect(toggle.controlAction == .toggle && toggle.controlValue == nil)
        #expect(CLI.parse(["headless-spotify", "control", "dance"]) == .failure(.unknownSubcommand("dance")))
        if case .failure(let error) = CLI.parse(["headless-spotify", "play"]) {
            #expect(error == .unknownSubcommand("play"))
        } else {
            Issue.record("expected unknownSubcommand for bare play")
        }
    }

    @Test("help text states the Sonar contract")
    func helpMentionsContract() {
        #expect(CLI.helpText.contains("com.spotify.client"))
        #expect(CLI.helpText.contains("status|hide|restore"))
    }
}

@Suite("SpotifyPlist against a fixture bundle")
struct SpotifyPlistTests {
    /// Build a minimal fake .app bundle in tmp.
    func makeFixture() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-test-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.spotify.client",
            "CFBundleName": "Spotify",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return dir.appendingPathComponent("Spotify.app").path
    }

    @Test("backup / set / read / restore round-trip")
    func roundTrip() throws {
        let app = try makeFixture()
        let plist = SpotifyPlist(appPath: app)
        #expect(try plist.readLSUIElement() == nil)
        try plist.setLSUIElement(true)
        #expect(try plist.readLSUIElement() == true)
        #expect(plist.hasBackup)
        // Second set must NOT clobber the original backup.
        try plist.setLSUIElement(true)
        try plist.restore()
        #expect(try plist.readLSUIElement() == nil)
        #expect(!plist.hasBackup)
    }

    @Test("restore without backup throws")
    func restoreWithoutBackupThrows() throws {
        let app = try makeFixture()
        let plist = SpotifyPlist(appPath: app)
        do {
            try plist.restore()
            Issue.record("expected backupMissing")
        } catch {
            #expect((error as? PlistError) == .backupMissing(plist.backupURL.path))
        }
    }

    @Test("missing app throws appNotFound")
    func missingAppThrows() {
        let plist = SpotifyPlist(appPath: "/nonexistent/Spotify.app")
        do {
            _ = try plist.readLSUIElement()
            Issue.record("expected appNotFound")
        } catch {
            #expect((error as? PlistError) == .appNotFound("/nonexistent/Spotify.app"))
        }
    }
}

@Suite("Runner dry-run (no side effects)")
struct RunnerDryRunTests {
    final class Lines: @unchecked Sendable { var values: [String] = [] }

    @Test("hide --dry-run prints plan, exit 0")
    func hideDryRun() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-dry-\(UUID().uuidString)/Spotify.app/Contents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.spotify.client"], format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("Info.plist"))
        let app = dir.deletingLastPathComponent().deletingLastPathComponent().path
        let lines = Lines()
        let code = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: app, dryRun: true),
            output: { lines.values.append($0) },
            errorOutput: { _ in }
        )
        #expect(code == 0)
        #expect(lines.values.joined().contains("LSUIElement=true"))
    }

    @Test("hide on missing app exits 2")
    func hideMissingApp() async {
        let errors = Lines()
        let code = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: "/nonexistent/Spotify.app"),
            output: { _ in },
            errorOutput: { errors.values.append($0) }
        )
        #expect(code == 2)
        #expect(!errors.values.isEmpty)
    }

    @Test("watch on missing app exits 2")
    func watchMissingApp() async {
        let lines = Lines()
        let code = await Runner.run(
            Invocation(subcommand: .watch, spotifyAppPath: "/nonexistent/Spotify.app"),
            output: { lines.values.append($0) },
            errorOutput: { _ in }
        )
        #expect(code == 2)
    }

    @Test("watch --dry-run prints plan, exit 0")
    func watchDryRun() async {
        let lines = Lines()
        let code = await Runner.run(
            Invocation(subcommand: .watch, dryRun: true),
            output: { lines.values.append($0) },
            errorOutput: { _ in }
        )
        #expect(code == 0)
        #expect(lines.values.joined().contains("watch plan"))
    }

    @Test("status JSON parses")
    func statusJsonParses() {
        let report = Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: true, running: true,
            lsuiElement: true, dock: .hidden, playerState: "playing", hasBackup: true
        )
        #expect(report.isReady)
        let json = Runner.jsonStatus(report)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["ready"] as? Bool == true)
        #expect(obj?["dock"] as? String == "hidden")
    }
}

@Suite("Watcher decision matrix")
struct WatcherTests {
    func report(
        installed: Bool = true, running: Bool = true, lsui: Bool? = true,
        dock: DockPresence = .hidden, player: String? = "playing"
    ) -> Runner.StatusReport {
        Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: installed, running: running,
            lsuiElement: lsui, dock: dock, playerState: player, hasBackup: true
        )
    }

    @Test("steady headless state → none")
    func steadyNone() {
        #expect(Watcher.decide(report: report(), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 0) == .none)
    }

    @Test("not installed / not running → none (never launch unasked)")
    func idleNone() {
        #expect(Watcher.decide(report: report(installed: false), lastSeenVersion: nil, currentVersion: nil, plistFailures: 0) == .none)
        #expect(Watcher.decide(report: report(running: false, dock: .notRunning, player: nil), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 0) == .none)
    }

    @Test("version change → reapplyPlist (update wiped it)")
    func updateReapplies() {
        let action = Watcher.decide(report: report(), lastSeenVersion: "1.0", currentVersion: "1.1", plistFailures: 0)
        #expect(action == .reapplyPlist(reason: "Spotify updated (1.0 → 1.1); re-applying LSUIElement"))
    }

    @Test("LSUIElement missing → reapplyPlist")
    func lsuiMissingReapplies() {
        let action = Watcher.decide(report: report(lsui: nil, dock: .visible), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 0)
        if case .reapplyPlist = action {} else { Issue.record("expected reapplyPlist, got \(action)") }
    }

    @Test("Dock visible once → relaunch; twice → injector fallback")
    func dockReturnEscalates() {
        let first = Watcher.decide(report: report(dock: .visible), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 0)
        if case .relaunchHeadless = first {} else { Issue.record("expected relaunchHeadless, got \(first)") }
        let second = Watcher.decide(report: report(dock: .visible), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 1)
        if case .injectorFallback = second {} else { Issue.record("expected injectorFallback, got \(second)") }
    }

    @Test("headless but mute → relaunch")
    func muteRelaunches() {
        let action = Watcher.decide(report: report(player: nil), lastSeenVersion: "1.0", currentVersion: "1.0", plistFailures: 0)
        if case .relaunchHeadless = action {} else { Issue.record("expected relaunchHeadless, got \(action)") }
    }
}

@Suite("Injector helpers")
struct InjectorTests {
    @Test("hardened runtime detected from codesign output")
    func hardenedDetected() {
        let hardened: SpotifyScripting.Runner = { _, _, _ in
            ProcessResult(exitCode: 0, stdout: "", stderr: "Identifier=com.spotify.client\nflags=0x10000(runtime) hashes=2551+7 location=embedded\n")
        }
        #expect(Injector.isHardenedRuntime(appPath: "/Applications/Spotify.app", run: hardened))
        let plain: SpotifyScripting.Runner = { _, _, _ in
            ProcessResult(exitCode: 0, stdout: "", stderr: "Identifier=com.example.Fixture\nflags=0x0(none) hashes=1+1 location=embedded\n")
        }
        #expect(!Injector.isHardenedRuntime(appPath: "/tmp/Fixture.app", run: plain))
    }

    /// Run `body` with HEADLESS_INJECTOR_DYLIB removed (parallel-safe).
    func withoutEnvOverride<T>(_ body: () throws -> T) rethrows -> T {
        let saved = ProcessInfo.processInfo.environment[Injector.envOverride]
        unsetenv(Injector.envOverride)
        defer {
            if let saved { setenv(Injector.envOverride, saved, 1) } else { unsetenv(Injector.envOverride) }
        }
        return try body()
    }

    @Test("locate order: explicit > env > installed")
    func locateOrder() throws {
        #expect(Injector.locate(explicit: "/tmp/a.dylib") == "/tmp/a.dylib")
        let saved = ProcessInfo.processInfo.environment[Injector.envOverride]
        setenv(Injector.envOverride, "/tmp/env.dylib", 1)
        #expect(Injector.locate(explicit: nil) == "/tmp/env.dylib")
        if let saved { setenv(Injector.envOverride, saved, 1) } else { unsetenv(Injector.envOverride) }
        try withoutEnvOverride {
            #expect(Injector.locate(explicit: "", cliBinaryPath: "/nonexistent/cli") == nil)
        }
    }

    @Test("locate finds brew-layout dylib relative to CLI")
    func locateBrewLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brew-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        let lib = root.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        let dylib = lib.appendingPathComponent(Injector.dylibFileName)
        try Data().write(to: dylib)
        try withoutEnvOverride {
            let found = Injector.locate(explicit: nil, cliBinaryPath: bin.appendingPathComponent("headless-spotify").path)
            #expect(found == dylib.standardized.path)
        }
    }
}

@Suite("AgentPlist")
struct AgentPlistTests {
    @Test("generated plist is valid XML with our label")
    func validPlist() throws {
        let text = AgentPlist.contents(binaryPath: "/usr/local/bin/headless-spotify", spotifyAppPath: "/Applications/Spotify.app", interval: 15)
        let data = text.data(using: .utf8)!
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any]
        #expect(obj?["Label"] as? String == AgentPlist.label)
        let args = obj?["ProgramArguments"] as? [String]
        #expect(args?.first == "/usr/local/bin/headless-spotify")
        #expect(args?.contains("watch") == true)
        #expect(obj?["KeepAlive"] as? Bool == true)
        let paths = obj?["WatchPaths"] as? [String]
        #expect(paths == ["/Applications/Spotify.app/Contents/Info.plist"])
    }

    @Test("agent path joins home correctly")
    func agentPath() {
        #expect(AgentPlist.agentPlistPath(homeDirectory: "/Users/ada") == "/Users/ada/Library/LaunchAgents/com.headless-spotify.watcher.plist")
    }
}
@Suite("hide/restore cycle on a fixture bundle (real plist + codesign, no relaunch)")
struct RunnerFixtureCycleTests {
    func makeFixture() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-cycle-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.spotify.client",
            "CFBundleShortVersionString": "9.9.9",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return dir.appendingPathComponent("Spotify.app").path
    }

    @Test("hide --skip-relaunch then restore --skip-relaunch round-trips")
    func hideRestoreCycle() async throws {
        let app = try makeFixture()
        let out = RunnerDryRunTests.Lines()
        let err = RunnerDryRunTests.Lines()

        let hideCode = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: app, skipRelaunch: true),
            output: { out.values.append($0) }, errorOutput: { err.values.append($0) }
        )
        #expect(hideCode == 0)
        #expect(try SpotifyPlist(appPath: app).readLSUIElement() == true)
        #expect(SpotifyPlist(appPath: app).hasBackup)

        let restoreCode = await Runner.run(
            Invocation(subcommand: .restore, spotifyAppPath: app, skipRelaunch: true),
            output: { out.values.append($0) }, errorOutput: { err.values.append($0) }
        )
        #expect(restoreCode == 0)
        #expect(try SpotifyPlist(appPath: app).readLSUIElement() == nil)
        #expect(!SpotifyPlist(appPath: app).hasBackup)
    }
}

@Suite("Control (stubbed runner)")
struct ControlTests {
    final class Calls: @unchecked Sendable { var scripts: [String] = [] }

    /// Stub: pgrep says running; osascript records the script, answers volume 70.
    func makeRun(calls: Calls) -> SpotifyScripting.Runner {
        { exe, args, _ in
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 0, stdout: "123\n", stderr: "") }
            let script = args.last ?? ""
            calls.scripts.append(script)
            if script.contains("get sound volume") {
                return ProcessResult(exitCode: 0, stdout: "70\n", stderr: "")
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    @Test("verbs map to exact AppleScript", arguments: [
        (ControlAction.play, "tell application \"Spotify\" to play"),
        (ControlAction.pause, "tell application \"Spotify\" to pause"),
        (ControlAction.toggle, "tell application \"Spotify\" to playpause"),
        (ControlAction.next, "tell application \"Spotify\" to next track"),
        (ControlAction.previous, "tell application \"Spotify\" to previous track"),
    ] as [(ControlAction, String)])
    func verbs(pair: (ControlAction, String)) {
        #expect(Control.script(for: pair.0) == pair.1)
    }

    @Test("volume math clamps 0–100")
    func volumeClamps() {
        #expect(Control.script(for: .setVolume, value: 150) == "tell application \"Spotify\" to set sound volume to 100")
        #expect(Control.script(for: .setVolume, value: -20) == "tell application \"Spotify\" to set sound volume to 0")
        #expect(Control.script(for: .volumeUp, currentVolume: 95) == "tell application \"Spotify\" to set sound volume to 100")
        #expect(Control.script(for: .volumeDown, currentVolume: 5) == "tell application \"Spotify\" to set sound volume to 0")
        #expect(Control.script(for: .setVolume) == nil)
    }

    @Test("perform sends the script, exit 0")
    func performOk() {
        let calls = Calls()
        let (code, line) = Control.perform(.next, run: makeRun(calls: calls))
        #expect(code == 0)
        #expect(calls.scripts == ["tell application \"Spotify\" to next track"])
        #expect(line == "next: ok")
    }

    @Test("volume-up reads then writes")
    func volumeUpTwoStep() {
        let calls = Calls()
        let (code, line) = Control.perform(.volumeUp, run: makeRun(calls: calls))
        #expect(code == 0)
        // get → set → confirm re-read
        #expect(calls.scripts.count == 3)
        #expect(calls.scripts[1] == "tell application \"Spotify\" to set sound volume to 80")
        #expect(line == "volume: 70")
    }

    @Test("not running refuses without launching")
    func notRunningGate() {
        let calls = Calls()
        let run: SpotifyScripting.Runner = { exe, _, _ in
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 1, stdout: "", stderr: "") }
            calls.scripts.append(exe)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let (code, _) = Control.perform(.play, run: run)
        #expect(code == 1)
        #expect(!calls.scripts.contains(where: { $0.contains("osascript") }))
    }

    @Test("set-volume without value is usage error")
    func setVolumeNeedsValue() {
        let calls = Calls()
        let (code, _) = Control.perform(.setVolume, run: makeRun(calls: calls))
        #expect(code == 2)
        #expect(calls.scripts.isEmpty)
    }

    @Test("Runner.control rejects missing action")
    func runnerMissingAction() {
        let errors = RunnerDryRunTests.Lines()
        let code = Runner.control(
            Invocation(subcommand: .control),
            output: { _ in }, errorOutput: { errors.values.append($0) }
        )
        #expect(code == 2)
    }
}

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("hung child is killed after timeout")
    func timeoutKills() {
        let result = ProcessRunner.run("/bin/sleep", ["30"], timeout: 1)
        #expect(result.timedOut)
        #expect(result.exitCode == 124)
    }

    @Test("fast child unaffected")
    func fastChild() {
        let result = ProcessRunner.run("/bin/echo", ["hi"], timeout: 10)
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hi")
    }
}

@Suite("SpotifyScripting with stubbed runner")
struct ScriptingTests {
    final class Box: @unchecked Sendable {        var calls: [String] = []
        var n = 0
    }

    @Test("not running short-circuits osascript")
    func notRunningShortCircuits() {
        let box = Box()
        let run: SpotifyScripting.Runner = { exe, args, _ in
            box.calls.append(exe + " " + args.joined(separator: " "))
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 1, stdout: "", stderr: "") }
            return ProcessResult(exitCode: 0, stdout: "playing\n", stderr: "")
        }
        #expect(SpotifyScripting.isSpotifyRunning(run: run) == false)
        #expect(SpotifyScripting.playerState(run: run) == nil)
        #expect(!box.calls.contains(where: { $0.contains("osascript") }))
    }

    @Test("waitForScripting polls until answered")
    func pollsUntilAnswered() {
        let box = Box()
        let run: SpotifyScripting.Runner = { exe, _, _ in
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 0, stdout: "123\n", stderr: "") }
            box.n += 1
            if box.n < 3 { return ProcessResult(exitCode: 1, stdout: "", stderr: "not running") }
            return ProcessResult(exitCode: 0, stdout: "paused\n", stderr: "")
        }
        let state = SpotifyScripting.waitForScripting(timeout: 10, pollInterval: 0, run: run, sleep: { _ in })
        #expect(state == "paused")
        #expect(box.n == 3)
    }
}
