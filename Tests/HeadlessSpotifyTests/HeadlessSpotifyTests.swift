import Foundation
import Testing

@testable import HeadlessSpotify
import HeadlessSpotifyBarKit

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

    @Test("subcommands parse", arguments: ["status", "launch", "hide", "restore", "watch", "control"])
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
        #expect(CLI.helpText.contains("status|launch|hide|restore"))
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

/// Pins the `status --json` contract read by Sonar and trak. If this fails you
/// changed a public interface: add fields freely, but a rename/removal/retype
/// needs a `statusSchemaVersion` bump and a README "Companions" update.
@Suite("status --json contract (schema 1)")
struct StatusJSONContractTests {
    func decode(_ report: Runner.StatusReport) throws -> [String: Any] {
        let data = try #require(Runner.jsonStatus(report).data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("exact key set and schema version")
    func keySet() throws {
        let obj = try decode(Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: true, running: true,
            lsuiElement: true, dock: .hidden, playerState: "playing", hasBackup: true
        ))
        #expect(Runner.statusSchemaVersion == 1)
        #expect(obj["schema"] as? Int == 1)
        #expect(Set(obj.keys) == [
            "schema", "app", "bundle", "installed", "running", "lsui_element", "dock",
            "headless", "player_state", "scriptable", "backup_present", "ready",
        ])
    }

    @Test("field types and values, headless + ready")
    func typesReady() throws {
        let obj = try decode(Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: true, running: true,
            lsuiElement: true, dock: .hidden, playerState: "playing", hasBackup: true
        ))
        #expect(obj["app"] as? String == "/Applications/Spotify.app")
        #expect(obj["bundle"] as? String == "com.spotify.client")
        #expect(obj["installed"] as? Bool == true)
        #expect(obj["running"] as? Bool == true)
        #expect(obj["lsui_element"] as? Bool == true)
        #expect(obj["dock"] as? String == "hidden")
        #expect(obj["headless"] as? Bool == true)
        #expect(obj["player_state"] as? String == "playing")
        #expect(obj["scriptable"] as? Bool == true)
        #expect(obj["backup_present"] as? Bool == true)
        #expect(obj["ready"] as? Bool == true)
    }

    @Test("not running: nullable fields are JSON null, dock is not_running")
    func nullsWhenNotRunning() throws {
        let obj = try decode(Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: true, running: false,
            lsuiElement: nil, dock: .notRunning, playerState: nil, hasBackup: false
        ))
        #expect(obj["schema"] as? Int == 1)
        #expect(obj["lsui_element"] is NSNull)
        #expect(obj["player_state"] is NSNull)
        #expect(obj["dock"] as? String == DockPresence.notRunning.rawValue)
        #expect(obj["headless"] as? Bool == false)
        #expect(obj["ready"] as? Bool == false)
    }

    @Test("dock values are the documented set")
    func dockValues() {
        #expect([DockPresence.visible, .hidden, .prohibited, .notRunning].map(\.rawValue)
            == ["visible", "hidden", "prohibited", "notRunning"])
    }
}

@Suite("launch (injected hooks, never starts Spotify)")
struct LaunchTests {
    final class Lines: @unchecked Sendable { var values: [String] = [] }
    final class Flag: @unchecked Sendable { var value = false }

    func hooks(
        running: Bool, launched: Flag, launchError: Error? = nil, state: String? = "paused"
    ) -> Runner.LaunchHooks {
        Runner.LaunchHooks(
            isRunning: { running },
            launchHeadless: { _ in
                launched.value = true
                if let launchError { throw launchError }
            },
            waitForScripting: { _ in state }
        )
    }

    /// Any existing path stands in for Spotify.app; hooks do the launching.
    var existingApp: String { FileManager.default.temporaryDirectory.path }

    @Test("already running → no-op, exit 0, no launch")
    func alreadyRunning() async {
        let launched = Flag(), out = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: "/nonexistent/Spotify.app"),
            output: { out.values.append($0) }, errorOutput: { _ in },
            hooks: hooks(running: true, launched: launched)
        )
        #expect(code == 0)
        #expect(!launched.value)
        #expect(out.values.joined().contains("already running"))
    }

    @Test("not running → launches, answers scripting, exit 0")
    func launchesAndAnswers() async {
        let launched = Flag(), out = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: existingApp),
            output: { out.values.append($0) }, errorOutput: { _ in },
            hooks: hooks(running: false, launched: launched)
        )
        #expect(code == 0)
        #expect(launched.value)
        #expect(out.values.joined().contains("paused"))
    }

    @Test("no scripting answer within timeout → exit 1 with message")
    func timesOut() async {
        let launched = Flag(), err = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: existingApp, timeout: 3),
            output: { _ in }, errorOutput: { err.values.append($0) },
            hooks: hooks(running: false, launched: launched, state: nil)
        )
        #expect(code == 1)
        #expect(err.values.joined().contains("within 3s"))
    }

    @Test("launch error → exit 1")
    func launchFails() async {
        struct Boom: Error {}
        let launched = Flag(), err = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: existingApp),
            output: { _ in }, errorOutput: { err.values.append($0) },
            hooks: hooks(running: false, launched: launched, launchError: Boom())
        )
        #expect(code == 1)
        #expect(err.values.joined().contains("could not start"))
    }

    @Test("missing app → exit 1, no launch")
    func missingApp() async {
        let launched = Flag(), err = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: "/nonexistent/Spotify.app"),
            output: { _ in }, errorOutput: { err.values.append($0) },
            hooks: hooks(running: false, launched: launched)
        )
        #expect(code == 1)
        #expect(!launched.value)
        #expect(err.values.joined().contains("not found"))
    }

    @Test("--dry-run → plan, exit 0, no launch")
    func dryRun() async {
        let launched = Flag(), out = Lines()
        let code = await Runner.launch(
            Invocation(subcommand: .launch, spotifyAppPath: existingApp, dryRun: true),
            output: { out.values.append($0) }, errorOutput: { _ in },
            hooks: hooks(running: false, launched: launched)
        )
        #expect(code == 0)
        #expect(!launched.value)
        #expect(out.values.joined().contains("launch plan"))
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
    func hardenedDetected() async {
        let hardened: SpotifyScripting.Runner = { _, _, _ in
            ProcessResult(exitCode: 0, stdout: "", stderr: "Identifier=com.spotify.client\nflags=0x10000(runtime) hashes=2551+7 location=embedded\n")
        }
        #expect(await Injector.isHardenedRuntime(appPath: "/Applications/Spotify.app", run: hardened))
        let plain: SpotifyScripting.Runner = { _, _, _ in
            ProcessResult(exitCode: 0, stdout: "", stderr: "Identifier=com.example.Fixture\nflags=0x0(none) hashes=1+1 location=embedded\n")
        }
        #expect(await !Injector.isHardenedRuntime(appPath: "/tmp/Fixture.app", run: plain))
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inj-\(UUID().uuidString)")
        let installed = root.appendingPathComponent(Injector.dylibFileName)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: installed)
        #expect(Injector.locate(explicit: "/tmp/a.dylib", installedPath: installed.path) == "/tmp/a.dylib")
        let saved = ProcessInfo.processInfo.environment[Injector.envOverride]
        setenv(Injector.envOverride, "/tmp/env.dylib", 1)
        #expect(Injector.locate(explicit: nil, installedPath: installed.path) == "/tmp/env.dylib")
        if let saved { setenv(Injector.envOverride, saved, 1) } else { unsetenv(Injector.envOverride) }
        try withoutEnvOverride {
            // Nothing anywhere: a machine that has run install.sh really does
            // have /usr/local/lib/headless-spotify/…, and a test that fails
            // there is a test that fails on every machine that used the tool.
            let missing = root.appendingPathComponent("nowhere").path
            #expect(Injector.locate(explicit: "", cliBinaryPath: "/nonexistent/cli", installedPath: missing) == nil)
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
            // The installed-path probe sits between the env var and the
            // CLI-relative search, so it has to miss for this to be testing
            // the layout rather than whatever this machine happens to have.
            let missing = root.appendingPathComponent("nowhere").path
            let found = Injector.locate(
                explicit: nil,
                cliBinaryPath: bin.appendingPathComponent("headless-spotify").path,
                installedPath: missing
            )
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
    func performOk() async {
        let calls = Calls()
        let (code, line) = await Control.perform(.next, run: makeRun(calls: calls))
        #expect(code == 0)
        #expect(calls.scripts == ["tell application \"Spotify\" to next track"])
        #expect(line == "next: ok")
    }

    @Test("volume-up reads then writes")
    func volumeUpTwoStep() async {
        let calls = Calls()
        let (code, line) = await Control.perform(.volumeUp, run: makeRun(calls: calls))
        #expect(code == 0)
        // get → set → confirm re-read
        #expect(calls.scripts.count == 3)
        #expect(calls.scripts[1] == "tell application \"Spotify\" to set sound volume to 80")
        #expect(line == "volume: 70")
    }

    @Test("not running refuses without launching")
    func notRunningGate() async {
        let calls = Calls()
        let run: SpotifyScripting.Runner = { exe, _, _ in
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 1, stdout: "", stderr: "") }
            calls.scripts.append(exe)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let (code, _) = await Control.perform(.play, run: run)
        #expect(code == 1)
        #expect(!calls.scripts.contains(where: { $0.contains("osascript") }))
    }

    @Test("set-volume without value is usage error")
    func setVolumeNeedsValue() async {
        let calls = Calls()
        let (code, _) = await Control.perform(.setVolume, run: makeRun(calls: calls))
        #expect(code == 2)
        #expect(calls.scripts.isEmpty)
    }

    @Test("Runner.control rejects missing action")
    func runnerMissingAction() async {
        let errors = RunnerDryRunTests.Lines()
        let code = await Runner.control(
            Invocation(subcommand: .control),
            output: { _ in }, errorOutput: { errors.values.append($0) }
        )
        #expect(code == 2)
    }
}

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("hung child is killed after timeout")
    func timeoutKills() async {
        let result = await ProcessRunner.run("/bin/sleep", ["30"], timeout: 1)
        #expect(result.timedOut)
        #expect(result.exitCode == 124)
    }

    @Test("fast child unaffected")
    func fastChild() async {
        let result = await ProcessRunner.run("/bin/echo", ["hi"], timeout: 10)
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
    func notRunningShortCircuits() async {
        let box = Box()
        let run: SpotifyScripting.Runner = { exe, args, _ in
            box.calls.append(exe + " " + args.joined(separator: " "))
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 1, stdout: "", stderr: "") }
            return ProcessResult(exitCode: 0, stdout: "playing\n", stderr: "")
        }
        #expect(await SpotifyScripting.isSpotifyRunning(run: run) == false)
        #expect(await SpotifyScripting.playerState(run: run) == nil)
        #expect(!box.calls.contains(where: { $0.contains("osascript") }))
    }

    @Test("waitForScripting polls until answered")
    func pollsUntilAnswered() async {
        let box = Box()
        let run: SpotifyScripting.Runner = { exe, _, _ in
            if exe.hasSuffix("pgrep") { return ProcessResult(exitCode: 0, stdout: "123\n", stderr: "") }
            box.n += 1
            if box.n < 3 { return ProcessResult(exitCode: 1, stdout: "", stderr: "not running") }
            return ProcessResult(exitCode: 0, stdout: "paused\n", stderr: "")
        }
        let state = await SpotifyScripting.waitForScripting(timeout: 10, pollInterval: 0, run: run, sleep: { _ in })
        #expect(state == "paused")
        #expect(box.n == 3)
    }
}

@Suite("Menu bar extra")
struct MenuBarModelTests {
    @Test("menu is the project name + Quit, nothing else")
    func menuIsMinimal() {
        // Name and Quit are the only rows the AppKit glue hard-codes; the
        // toggle row is asserted in MenuBarToggleTests.
        let items = MenuBarModel.menuItems(version: "1.2.3")
        #expect(items.contains(MenuItemSpec(title: "headless-spotify 1.2.3", isEnabled: false)))
        #expect(items.contains(MenuItemSpec(title: MenuBarModel.quitTitle, action: .quit)))
        #expect(!items.contains { $0.action == .none && $0.isEnabled })
    }

    @Test("only the toggle and Quit are actionable")
    func onlyToggleAndQuitAreActionable() {
        let actions = MenuBarModel.menuItems(version: "0.1.0").filter { $0.isEnabled && !$0.isSeparator }
        #expect(actions.count == 2)
        #expect(actions.contains { $0.isQuit })
        #expect(actions.contains { $0.isToggle })
    }

    @Test("identifiers used by the AppKit glue stay stable")
    func identifiers() {
        #expect(MenuBarModel.projectName == "headless-spotify")
        #expect(MenuBarModel.quitTitle == "Quit headless-spotify")
        #expect(!MenuBarModel.iconSymbolName(hidingEnabled: true).isEmpty)
        #expect(!MenuBarModel.iconSymbolName(hidingEnabled: false).isEmpty)
    }
}

@Suite("Watcher backoff")
struct WatcherBackoffTests {
    @Test("no failures keeps the configured interval")
    func noBackoff() {
        #expect(Watcher.backoffInterval(base: 15, failures: 0) == 15)
    }

    @Test("doubles per consecutive failure, then caps")
    func doublesThenCaps() {
        #expect(Watcher.backoffInterval(base: 15, failures: 1) == 30)
        #expect(Watcher.backoffInterval(base: 15, failures: 2) == 60)
        #expect(Watcher.backoffInterval(base: 15, failures: 3) == 120)
        #expect(Watcher.backoffInterval(base: 15, failures: 4) == 240)
        // Capped: a Spotify build that can never be hidden must not spin.
        #expect(Watcher.backoffInterval(base: 15, failures: 10) == 240)
        #expect(Watcher.backoffInterval(base: 15, failures: 999) == 240)
    }

    @Test("degenerate inputs are safe")
    func degenerate() {
        #expect(Watcher.backoffInterval(base: 15, failures: -3) == 15)
        #expect(Watcher.backoffInterval(base: 0, failures: 5) == 0)
        #expect(Watcher.backoffInterval(base: 10, failures: 2, maxMultiplier: 1) == 10)
    }
}

@Suite("Menu bar toggle")
struct MenuBarToggleTests {
    @Test("the row shows current state, with a checkmark")
    func stateRow() {
        for enabled in [true, false] {
            let items = MenuBarModel.menuItems(version: "1.0", hidingEnabled: enabled)
            #expect(items[2].title == "Hidden from Dock")
            #expect(items[2].isToggle && items[2].isEnabled)
            #expect(items[2].state == (enabled ? .on : .off), "checkmark must match reality")
        }
    }

    @Test("one click flips the state it reported")
    func clickFlipsState() {
        // on -> the next action is restore, off -> hide.
        #expect(ToggleAction(hidingEnabled: true) == .disable)
        #expect(ToggleAction(hidingEnabled: false) == .enable)
    }

    @Test("icon and tooltip follow the state")
    func iconFollowsState() {
        #expect(MenuBarModel.iconSymbolName(hidingEnabled: true) == "eye.slash")
        #expect(MenuBarModel.iconSymbolName(hidingEnabled: false) == "music.note")
        #expect(MenuBarModel.iconSymbolName(hidingEnabled: true) != MenuBarModel.iconSymbolName(hidingEnabled: false))
        #expect(MenuBarModel.tooltip(hidingEnabled: true).contains("hidden"))
        #expect(MenuBarModel.tooltip(hidingEnabled: false).contains("shows"))
    }

    @Test("menu is name, toggle, Quit")
    func menuShape() {
        let off = MenuBarModel.menuItems(version: "1.0", hidingEnabled: false)
        #expect(off.count == 5)
        #expect(off[0].title == "headless-spotify 1.0" && !off[0].isEnabled)
        #expect(off[1].isSeparator)
        #expect(off[2].isToggle)
        #expect(off[3].isSeparator)
        #expect(off[4].isQuit && off[4].isEnabled)
    }

    @Test("a granted Automation shows no extra row")
    func noPermissionRowWhenGranted() {
        let items = MenuBarModel.menuItems(version: "1.0", automation: .granted)
        #expect(items.count == 5, "granted must not change the menu")
        #expect(!items.contains { $0.isPermissionRequest })
    }

    @Test("an unread Automation shows no row either")
    func noPermissionRowWhenUnknown() {
        // A row that appears and then vanishes under the cursor is worse than
        // one that is briefly absent.
        let items = MenuBarModel.menuItems(version: "1.0", automation: .unknown)
        #expect(items.count == 5)
        #expect(!items.contains { $0.isPermissionRequest })
    }

    @Test("a missing Automation offers a clickable row above the toggle")
    func permissionRowWhenNeeded() {
        let items = MenuBarModel.menuItems(version: "1.0", automation: .needsGrant)
        #expect(items.count == 6)
        let row = items[2]
        #expect(row.isPermissionRequest)
        #expect(row.isEnabled, "clicking is what makes macOS prompt")
        #expect(row.title == Automation.permissionTitle)
        // Above the toggle: a missing permission makes the toggle do nothing,
        // so the explanation must not be buried under the thing that does
        // nothing.
        #expect(items[3].isToggle)
    }

    @Test("a refused Automation explains itself and is not clickable")
    func permissionRowWhenRefused() {
        let items = MenuBarModel.menuItems(version: "1.0", automation: .refused)
        let row = items[2]
        #expect(row.title == Automation.blockedTitle)
        #expect(!row.isEnabled, "a refused grant cannot be re-requested")
        #expect(!row.isPermissionRequest, "clicking would silently do nothing")
    }

    @Test("the permission row sits between the separator and the toggle")
    func permissionRowPlacement() {
        let items = MenuBarModel.menuItems(version: "1.0", message: "hi", automation: .needsGrant)
        #expect(items[0].title.hasPrefix("headless-spotify"))
        #expect(items[1].isSeparator)
        #expect(items[2].isPermissionRequest)
        #expect(items[3].isToggle)
        #expect(items[4].title == "hi")
        #expect(items[5].isSeparator)
        #expect(items[6].isQuit)
    }

    @Test("Automation state helpers")
    func automationHelpers() {
        #expect(AutomationState.granted.isGranted)
        #expect(!AutomationState.unknown.isGranted)
        #expect(AutomationState.needsGrant.canPrompt)
        #expect(!AutomationState.refused.canPrompt, "the OS will not ask again")
        #expect(!AutomationState.granted.canPrompt)
        #expect(Automation.spotifyBundleID == "com.spotify.client")
    }

    @Test("the permission copy names the app and the choice")
    func permissionCopy() {
        #expect(Automation.permissionTitle.localizedCaseInsensitiveContains("spotify"))
        #expect(Automation.permissionMessage.contains("OK"))
        #expect(Automation.blockedMessage.contains("System Settings"))
    }

    @Test("a successful probe means granted")
    func probeGranted() {
        #expect(Automation.state(exitCode: 0, standardError: "") == .granted)
    }

    @Test("-1743 is a refusal, and cannot be re-asked")
    func probeRefused() {
        let err = "execution error: Not authorized to send Apple events to «application Spotify». (-1743)"
        #expect(Automation.state(exitCode: 1, standardError: err) == .refused)
    }

    @Test("-1744 means the OS would still prompt, so a click can fix it")
    func probeNeedsGrant() {
        let err = "execution error: (-1744)"
        #expect(Automation.state(exitCode: 1, standardError: err) == .needsGrant)
    }

    @Test("Spotify not running is not a permission problem")
    func probeTargetNotRunning() {
        // Must not read as a denial: sending a user to System Settings for a
        // grant that does not exist yet is the failure this avoids.
        let err = "execution error: Can't get application \"Spotify\". (-600)"
        #expect(Automation.state(exitCode: 1, standardError: err) == .unknown)
    }

    @Test("an unrecognised failure shows no row rather than a wrong one")
    func probeUnknown() {
        #expect(Automation.state(exitCode: 1, standardError: "") == .unknown)
        #expect(Automation.state(exitCode: 127, standardError: "not found") == .unknown)
        #expect(Automation.state(exitCode: 1, standardError: "something else entirely") == .unknown)
    }

    @Test("the status codes are matched as numbers, not prose")
    func probeMatchesNumbers() {
        // The prose is localised; the numbers are not. A probe that matched the
        // English message would report "granted" on a non-English system.
        let localised = "execution error: Nicht autorisiert, Apple-Events zu senden. (-1743)"
        #expect(Automation.state(exitCode: 1, standardError: localised) == .refused)
    }

    @Test("the probe script is the one the CLI uses")
    func probeScriptShape() {
        #expect(Automation.probeScript.contains("get player state"))
        #expect(Automation.osascript == "/usr/bin/osascript")
    }

    @Test("missing CLI disables the toggle instead of failing")
    func missingCLI() {
        let items = MenuBarModel.menuItems(version: "1.0", hidingEnabled: false, cliAvailable: false)
        #expect(items[2].title == MenuBarModel.cliMissingTitle)
        #expect(!items[2].isEnabled)
        #expect(!items[2].isToggle)
        #expect(items[4].isQuit, "Quit stays available")
    }

    @Test("a running toggle cannot be started twice")
    func busyDisablesToggle() {
        let items = MenuBarModel.menuItems(version: "1.0", hidingEnabled: true, busy: true)
        #expect(items[2].title == MenuBarModel.busyTitle)
        #expect(!items[2].isEnabled)
        #expect(!items[2].isToggle)
        #expect(items[2].state == .on, "still shows what is true while working")
    }

    @Test("last result shows as an informational row")
    func messageRow() {
        let items = MenuBarModel.menuItems(version: "1.0", message: "hide: not writable")
        #expect(items.count == 6)
        #expect(items[3].title == "hide: not writable")
        #expect(!items[3].isEnabled)
        #expect(items[5].isQuit)
    }

    @Test("status message takes one trimmed line and caps length")
    func statusMessage() {
        #expect(MenuBarModel.statusMessage(nil) == nil)
        #expect(MenuBarModel.statusMessage("  \n ") == nil)
        #expect(MenuBarModel.statusMessage("\n first line \nsecond line") == "first line")
        let long = String(repeating: "x", count: 200)
        let capped = MenuBarModel.statusMessage(long)
        #expect(capped?.count == 60)
        #expect(capped?.hasSuffix("…") == true)
    }
}

@Suite("Hiding state probe")
struct HidingStateTests {
    func plist(_ lsui: Any?) -> Data {
        var dict: [String: Any] = ["CFBundleIdentifier": "com.spotify.client"]
        if let lsui { dict["LSUIElement"] = lsui }
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    @Test("LSUIElement drives the toggle state")
    func readsKey() {
        #expect(HidingState.hidingEnabled(plistData: plist(true)) == true)
        #expect(HidingState.hidingEnabled(plistData: plist(false)) == false)
        #expect(HidingState.hidingEnabled(plistData: plist(nil)) == false)
    }

    @Test("garbage is not hiding")
    func garbage() {
        #expect(HidingState.hidingEnabled(plistData: Data("not a plist".utf8)) == false)
        #expect(HidingState.hidingEnabled(plistData: Data()) == false)
    }
}

@Suite("CLI lookup for the menu bar toggle")
struct CLILocatorTests {
    @Test("env override wins, then install prefixes, then siblings")
    func order() {
        let paths = CLILocator.candidates(
            env: [CLILocator.envOverride: "/custom/cli"],
            barExecutablePath: "/Applications/headless-spotify.app/Contents/MacOS/headless-spotify-bar"
        )
        #expect(paths.first == "/custom/cli")
        #expect(paths.contains("/usr/local/bin/headless-spotify"))
        #expect(paths.contains("/opt/homebrew/bin/headless-spotify"))
        #expect(paths.contains("/Applications/headless-spotify.app/Contents/MacOS/headless-spotify"))
    }

    @Test("candidates are de-duplicated")
    func dedupes() {
        let paths = CLILocator.candidates(
            env: [:],
            barExecutablePath: "/usr/local/bin/headless-spotify-bar"
        )
        #expect(paths.filter { $0 == "/usr/local/bin/headless-spotify" }.count == 1)
        #expect(Set(paths).count == paths.count)
    }

    @Test("resolve picks the first that exists, else nil")
    func resolves() {
        #expect(
            CLILocator.resolve(
                env: [CLILocator.envOverride: "/nope/a"],
                barExecutablePath: nil,
                exists: { _ in false }
            ) == nil
        )
        #expect(
            CLILocator.resolve(
                env: [CLILocator.envOverride: "/nope/a"],
                barExecutablePath: nil,
                exists: { $0 == "/usr/local/bin/headless-spotify" }
            ) == "/usr/local/bin/headless-spotify"
        )
    }
}

@Suite("Toggle command plan")
struct TogglePlanTests {
    let cli = "/usr/local/bin/headless-spotify"
    let app = "/Applications/Spotify.app"

    @Test("writable bundle: one call as the user")
    func writable() {
        let enable = TogglePlan.commands(action: .enable, cliPath: cli, spotifyAppPath: app, bundleWritable: true)
        #expect(enable.count == 1)
        #expect(enable[0].executable == cli)
        #expect(enable[0].arguments == ["hide", "--spotify-app", app])
        let disable = TogglePlan.commands(action: .disable, cliPath: cli, spotifyAppPath: app, bundleWritable: true)
        #expect(disable[0].arguments.first == "restore")
    }

    @Test("root-owned bundle: admin prompt for the plist, relaunch as the user")
    func needsAdmin() {
        let plan = TogglePlan.commands(action: .enable, cliPath: cli, spotifyAppPath: app, bundleWritable: false)
        #expect(plan.count == 2)
        #expect(plan[0].executable == TogglePlan.osascript)
        #expect(plan[0].arguments.first == "-e")
        #expect(plan[0].arguments[1].contains("with administrator privileges"))
        #expect(plan[0].arguments[1].contains("'hide' '--skip-relaunch'"))
        #expect(!plan[0].arguments[1].contains("--skip-plist"), "the user half must relaunch, not the root half")
        #expect(plan[1].executable == cli)
        #expect(plan[1].arguments == ["hide", "--skip-plist", "--spotify-app", app])
    }

    @Test("paths with spaces stay one argument")
    func quoting() {
        let plan = TogglePlan.commands(
            action: .disable,
            cliPath: "/Users/me/My Tools/headless-spotify",
            spotifyAppPath: "/Volumes/Music/Spotify.app",
            bundleWritable: false
        )
        let script = plan[0].arguments[1]
        #expect(script.contains("'/Users/me/My Tools/headless-spotify'"))
        #expect(script.contains("'/Volumes/Music/Spotify.app'"))
    }

    @Test("shell + AppleScript quoting is escaped")
    func escaping() {
        #expect(TogglePlan.shellQuote("plain") == "'plain'")
        #expect(TogglePlan.shellQuote("it's") == #"'it'\''s'"#)
        let script = TogglePlan.elevatedScript(cliPath: "/a b/cli", arguments: ["hide"])
        #expect(script == #"do shell script "'/a b/cli' 'hide'" with administrator privileges"#)
        let quoted = TogglePlan.elevatedScript(cliPath: #"/odd"name"#, arguments: [])
        #expect(quoted.contains(#"\""#), "double quotes must be escaped for AppleScript")
    }
}

@Suite("Watcher leaves un-hideable Spotify alone")
struct WatcherUnhideableTests {
    func report(lsui: Bool? = true, dock: DockPresence = .hidden) -> Runner.StatusReport {
        Runner.StatusReport(
            appPath: "/Applications/Spotify.app", installed: true, running: true,
            lsuiElement: lsui, dock: dock, playerState: "playing", hasBackup: false
        )
    }

    @Test("a version that already failed is left completely alone")
    func handsOffKnownBadVersion() {
        // LSUIElement is absent (we rolled back) and the Dock is visible: every
        // other signal says "re-apply", but this version is known-bad.
        let action = Watcher.decide(
            report: report(lsui: nil, dock: .visible),
            lastSeenVersion: "1.3.1", currentVersion: "1.3.1",
            plistFailures: 3, unhideableVersion: "1.3.1"
        )
        #expect(action == .none, "must not quit/relaunch a Spotify it cannot fix")
    }

    @Test("a different version is still worth trying")
    func retriesAfterUpdate() {
        let action = Watcher.decide(
            report: report(lsui: nil, dock: .visible),
            lastSeenVersion: "1.3.1", currentVersion: "1.4.0",
            plistFailures: 3, unhideableVersion: "1.3.1"
        )
        #expect(action == .reapplyPlist(reason: "Spotify updated (1.3.1 → 1.4.0); re-applying LSUIElement"))
    }

    @Test("without a blocked version nothing changes")
    func normalBehaviour() {
        let action = Watcher.decide(
            report: report(lsui: nil, dock: .visible),
            lastSeenVersion: "1.3.1", currentVersion: "1.3.1",
            plistFailures: 0, unhideableVersion: nil
        )
        if case .reapplyPlist = action {} else { #expect(Bool(false), "got \(action)") }
    }

    @Test("threshold is small enough to stop interference quickly")
    func threshold() {
        #expect(Watcher.unhideableThreshold == 3)
    }
}

@Suite("Restore never applies a stale backup")
struct StaleBackupTests {
    /// Fixture with a version, hidden (LSUIElement=true) plus a backup taken
    /// from a DIFFERENT version — i.e. Spotify updated while hidden.
    func makeUpdatedWhileHidden() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-stale-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = SpotifyPlist(appPath: dir.appendingPathComponent("Spotify.app").path)
        let original: [String: Any] = [
            "CFBundleIdentifier": "com.spotify.client",
            "CFBundleShortVersionString": "1.2.0",
            "NewKeyFromOldVersion": "keep-me",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try data.write(to: plist.infoPlistURL)
        try plist.setLSUIElement(true) // backs up 1.2.0 and records it

        // Spotify auto-updates: new version, new plist, backup left behind.
        let updated: [String: Any] = [
            "CFBundleIdentifier": "com.spotify.client",
            "CFBundleShortVersionString": "1.3.1",
            "KeyOnlyNewVersionHas": "do-not-strip",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: updated, format: .xml, options: 0)
            .write(to: plist.infoPlistURL)
        return plist.appPath
    }

    @Test("mismatch is detected")
    func detectsMismatch() throws {
        let app = try makeUpdatedWhileHidden()
        let plist = SpotifyPlist(appPath: app)
        #expect(plist.backedUpAppVersion() == "1.2.0")
        #expect(plist.appVersion() == "1.3.1")
        #expect(plist.backupVersionMismatch())
    }

    @Test("same version is not a mismatch")
    func sameVersion() throws {
        let app = try makeUpdatedWhileHidden()
        let plist = SpotifyPlist(appPath: app)
        _ = try plist.removeLSUIElementOnly()
        // Re-hide so the recorded version matches the installed one again.
        try plist.setLSUIElement(true)
        #expect(plist.backedUpAppVersion() == "1.3.1")
        #expect(plist.backupVersionMismatch() == false)
    }

    @Test("safe restore keeps the new version's keys and drops our key")
    func safeRestore() async throws {
        let app = try makeUpdatedWhileHidden()
        let plist = SpotifyPlist(appPath: app)
        try plist.removeLSUIElementOnly()
        #expect(try plist.readLSUIElement() == nil, "our key must be gone")
        #expect(try plist.appVersion() == "1.3.1", "new version must survive")
        let data = try Data(contentsOf: plist.infoPlistURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let dict = try #require(
            PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any]
        )
        #expect(dict["KeyOnlyNewVersionHas"] as? String == "do-not-strip", "must not strip the new version's keys")
        #expect(!plist.hasBackup)
    }

    @Test("normal restore still round-trips byte-for-byte")
    func normalRestore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-fresh-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = SpotifyPlist(appPath: dir.appendingPathComponent("Spotify.app").path)
        let original: [String: Any] = [
            "CFBundleIdentifier": "com.spotify.client",
            "CFBundleShortVersionString": "2.0.0",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: original, format: .xml, options: 0)
            .write(to: plist.infoPlistURL)
        let before = try Data(contentsOf: plist.infoPlistURL)
        try plist.setLSUIElement(true)
        try plist.restore()
        #expect(try Data(contentsOf: plist.infoPlistURL) == before, "untouched bundle must come back exactly")
    }
}

@Suite("hide refuses to touch another app")
struct BundleGuardTests {
    func fixture(bundleID: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-guard-\(UUID().uuidString)/Spotify.app/Contents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": "1.0.0",
            ], format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("Info.plist"))
        return dir.deletingLastPathComponent().path
    }

    @Test("a non-Spotify bundle is refused and left untouched", arguments: [
        "com.apple.Safari", "com.example.Thing", "com.spotify.client.beta",
    ])
    func refusesOtherApps(bundleID: String) async throws {
        let app = try fixture(bundleID: bundleID)
        let errors = RunnerDryRunTests.Lines()
        let code = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: app, skipRelaunch: true),
            output: { _ in }, errorOutput: { errors.values.append($0) }
        )
        #expect(code == 2)
        #expect(errors.values.joined().contains("refusing to edit it"))
        let plist = SpotifyPlist(appPath: app)
        #expect(try plist.readLSUIElement() == nil, "the other app must not be modified")
        #expect(!plist.hasBackup, "and must not be left with our backup files")
    }

    @Test("--force overrides the guard")
    func forceOverrides() async throws {
        let app = try fixture(bundleID: "com.example.Thing")
        let code = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: app, skipRelaunch: true, force: true),
            output: { _ in }, errorOutput: { _ in }
        )
        #expect(code == 0)
        #expect(try SpotifyPlist(appPath: app).readLSUIElement() == true)
    }

    @Test("real Spotify is still allowed")
    func allowsSpotify() async throws {
        let app = try fixture(bundleID: CLI.bundleID)
        let code = await Runner.run(
            Invocation(subcommand: .hide, spotifyAppPath: app, skipRelaunch: true),
            output: { _ in }, errorOutput: { _ in }
        )
        #expect(code == 0)
        #expect(try SpotifyPlist(appPath: app).readLSUIElement() == true)
    }

    @Test("--force parses")
    func forceFlag() throws {
        #expect(try CLI.parse(["headless-spotify", "hide", "--force"]).get().force)
        #expect(try CLI.parse(["headless-spotify", "hide"]).get().force == false)
    }
}

@Suite("ProcessRunner does not deadlock on chatty children")
struct ProcessRunnerOutputTests {
    /// A child that writes far more than a pipe buffer (~64 KB) before exiting.
    /// Reading the pipe only after exit would hang until the timeout.
    @Test("large stdout is drained, not deadlocked")
    func largeStdout() async {
        let script = """
            import Foundation
            let chunk = String(repeating: "x", count: 65_536)
            for _ in 0..<8 { FileHandle.standardOutput.write(Data(chunk.utf8)) }
            """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chatty-\(UUID().uuidString).swift")
        try? Data(script.utf8).write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Compile once with the CLT-available swift, then run the produced binary.
        let binary = dir.deletingPathExtension()
        let compile = await ProcessRunner.run("/usr/bin/xcrun", ["swiftc", "-O", dir.path, "-o", binary.path], timeout: 180)
        guard compile.exitCode == 0 else {
            Issue.record("could not compile chatty fixture: \(compile.stderr)")
            return
        }
        let result = await ProcessRunner.run(binary.path, [], timeout: 30)
        #expect(result.exitCode == 0)
        #expect(!result.timedOut, "a chatty child must not hit the timeout")
        #expect(result.stdout.utf8.count == 8 * 65_536)
    }

    @Test("output produced before a timeout is still reported")
    func partialOutputOnTimeout() async {
        // Writes a line, then sleeps past the timeout.
        let result = await ProcessRunner.run("/bin/sh", ["-c", "echo started; sleep 30"], timeout: 1.5)
        #expect(result.timedOut)
        #expect(result.exitCode == 124)
        #expect(result.stdout.contains("started"), "partial output must not be thrown away")
    }

    /// Regression: waiting on a child must not block a *cooperative* thread.
    /// The pool is sized to the core count, so enough concurrent children used
    /// to occupy every thread and deadlock the whole test run. This ran far
    /// more children than any machine has cores and must still finish.
    @Test("many concurrent children do not exhaust the cooperative pool")
    func concurrentChildrenDoNotStarveThePool() async {
        let count = 40
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for i in 0..<count {
                group.addTask {
                    let r = await ProcessRunner.run("/bin/echo", ["child-\(i)"], timeout: 30)
                    return r.exitCode == 0 && r.stdout.contains("child-\(i)")
                }
            }
            var collected: [Bool] = []
            for await ok in group { collected.append(ok) }
            return collected
        }
        #expect(results.count == count)
        #expect(results.allSatisfy { $0 }, "every concurrent child must return its own output")
    }
}

@Suite("Editing a bundle must not change its permissions")
struct PlistWriteTests {
    func fixture() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-perm-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = SpotifyPlist(appPath: dir.appendingPathComponent("Spotify.app").path)
        try PropertyListSerialization
            .data(fromPropertyList: ["CFBundleIdentifier": "com.spotify.client"], format: .xml, options: 0)
            .write(to: plist.infoPlistURL)
        return plist.appPath
    }

    @Test("file mode survives the edit")
    func modePreserved() throws {
        let app = try fixture()
        let plist = SpotifyPlist(appPath: app)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plist.infoPlistURL.path)
        try plist.setLSUIElement(true)
        let mode = try FileManager.default
            .attributesOfItem(atPath: plist.infoPlistURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o600, "an atomic write must not reset the bundle's mode")
        #expect(try plist.readLSUIElement() == true, "and the edit must still have happened")
    }

    @Test("the usual 0644 mode is left alone")
    func commonModePreserved() throws {
        let app = try fixture()
        let plist = SpotifyPlist(appPath: app)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.infoPlistURL.path)
        try plist.setLSUIElement(true)
        let mode = try FileManager.default
            .attributesOfItem(atPath: plist.infoPlistURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o644)
    }
}

@Suite("LaunchAgent plist is always parseable")
struct AgentPlistEscapingTests {
    @Test("paths with XML characters produce valid plist XML")
    func escapesPaths() throws {
        let nasty = "/Volumes/R&D/<Music>/Spotify \"Final\".app"
        let text = AgentPlist.contents(binaryPath: "/usr/local/bin/headless & co", spotifyAppPath: nasty, interval: 15)
        let data = try #require(text.data(using: .utf8))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try #require(
            PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any]
        )
        let args = try #require(obj["ProgramArguments"] as? [String])
        #expect(args.first == "/usr/local/bin/headless & co")
        #expect(args.contains(nasty))
        let paths = try #require(obj["WatchPaths"] as? [String])
        #expect(paths == ["\(nasty)/Contents/Info.plist"])
    }
}

@Suite("restore does not disturb an untouched Spotify")
struct RestoreNoOpTests {
    func untouchedFixture() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-noop-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Spotify.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = SpotifyPlist(appPath: dir.appendingPathComponent("Spotify.app").path)
        try PropertyListSerialization
            .data(fromPropertyList: ["CFBundleIdentifier": "com.spotify.client"], format: .xml, options: 0)
            .write(to: plist.infoPlistURL)
        return plist.appPath
    }

    @Test("a restore with nothing to undo returns success and says so")
    func noOpRestore() async throws {
        let app = try untouchedFixture()
        let lines = RunnerDryRunTests.Lines()
        let code = await Runner.run(
            Invocation(subcommand: .restore, spotifyAppPath: app),
            output: { lines.values.append($0) }, errorOutput: { _ in }
        )
        #expect(code == 0)
        let text = lines.values.joined(separator: "\n")
        #expect(text.contains("nothing to change"), "got: \(text)")
        #expect(text.contains("left Spotify running untouched"), "must not relaunch")
    }

    @Test("a real restore still reports the relaunch")
    func realRestore() async throws {
        let app = try untouchedFixture()
        let plist = SpotifyPlist(appPath: app)
        try plist.setLSUIElement(true)
        let lines = RunnerDryRunTests.Lines()
        _ = await Runner.run(
            Invocation(subcommand: .restore, spotifyAppPath: app, skipRelaunch: true),
            output: { lines.values.append($0) }, errorOutput: { _ in }
        )
        #expect(lines.values.joined().contains("original Info.plist"))
    }
}

@Suite("Gatekeeper quarantine on the CLI")
struct QuarantineTests {
    /// A fake xattr: records the calls and answers from a mutable script.
    ///
    /// Synchronous on purpose. `Quarantine.Runner` is async only so the call
    /// sites read the same as the CLI's own runner; nothing in the fake needs
    /// to suspend, and holding an `NSLock` across an `await` is exactly the
    /// mistake Swift 6 rejects.
    private final class FakeXattr: @unchecked Sendable {
        struct Call: Equatable {
            var executable: String
            var arguments: [String]
        }
        private var recorded: [Call] = []
        private var quarantined: Set<String>
        /// Set when the delete should fail, to model a file the user cannot write.
        var deleteFails = false

        init(quarantined: Set<String>) { self.quarantined = quarantined }

        var calls: [Call] { recorded }

        func answer(_ executable: String, _ arguments: [String]) -> Int32 {
            recorded.append(Call(executable: executable, arguments: arguments))
            let path = arguments.last ?? ""
            if arguments.first == "-p" {
                return quarantined.contains(path) ? 0 : 1
            }
            if arguments.first == "-dr" {
                guard !deleteFails else { return 1 }
                quarantined.remove(path)
                return 0
            }
            return 1
        }

        var runner: Quarantine.Runner { { [self] exe, args in answer(exe, args) } }
    }

    @Test("an unquarantined CLI is left alone")
    func cleanFileIsUntouched() async {
        let fake = FakeXattr(quarantined: [])
        let cleared = await Quarantine.clearIfNeeded(at: "/opt/homebrew/bin/headless-spotify", run: fake.runner)
        #expect(cleared, "a file with no attribute is already clear")
        // One probe and nothing else. The probe is unavoidable — it is how we
        // learn there is nothing to do — but no delete may be issued.
        #expect(fake.calls.count == 1, "expected only a probe, got \(fake.calls)")
        #expect(fake.calls[0].arguments == ["-p", Quarantine.attribute, "/opt/homebrew/bin/headless-spotify"])
    }

    @Test("a quarantined CLI is cleared before it is run")
    func quarantinedFileIsCleared() async {
        let cli = "/opt/homebrew/Caskroom/headless-spotify/0.1.0/bin/headless-spotify"
        let fake = FakeXattr(quarantined: [cli])
        let cleared = await Quarantine.clearIfNeeded(at: cli, run: fake.runner)
        #expect(cleared)
        // Probe, delete, probe again: the result is verified, not assumed.
        #expect(fake.calls.count == 3, "expected probe, delete, probe; got \(fake.calls)")
        #expect(fake.calls[0].arguments == ["-p", Quarantine.attribute, cli])
        #expect(fake.calls[1] == .init(executable: Quarantine.xattr,
                                       arguments: ["-dr", Quarantine.attribute, cli]))
        #expect(fake.calls[2].arguments == ["-p", Quarantine.attribute, cli])
    }

    @Test("a failed delete is reported rather than claimed as fixed")
    func failedDeleteIsNotSuccess() async {
        let cli = "/opt/homebrew/bin/headless-spotify"
        let fake = FakeXattr(quarantined: [cli])
        fake.deleteFails = true
        let cleared = await Quarantine.clearIfNeeded(at: cli, run: fake.runner)
        #expect(!cleared, "the caller must be able to tell the user it did not work")
    }

    @Test("an empty path is refused without running anything")
    func emptyPath() async {
        let fake = FakeXattr(quarantined: [])
        let cleared = await Quarantine.clearIfNeeded(at: "", run: fake.runner)
        #expect(!cleared)
        #expect(fake.calls.isEmpty)
    }

    @Test("the attribute and the tool are the real ones")
    func constants() {
        #expect(Quarantine.attribute == "com.apple.quarantine")
        #expect(Quarantine.xattr == "/usr/bin/xattr")
    }

    @Test("the probe asks xattr the question xattr answers with an exit code")
    func probeUsesExitCode() async {
        let fake = FakeXattr(quarantined: ["/x"])
        #expect(await Quarantine.isQuarantined("/x", run: fake.runner))
        #expect(!(await Quarantine.isQuarantined("/y", run: fake.runner)))
    }

    @Test("only the one file is touched, never a parent directory")
    func scopeIsOneFile() async {
        let cli = "/opt/homebrew/Caskroom/headless-spotify/0.1.0/bin/headless-spotify"
        let fake = FakeXattr(quarantined: [cli])
        _ = await Quarantine.clearIfNeeded(at: cli, run: fake.runner)
        for call in fake.calls {
            #expect(call.arguments.last == cli, "every call must name exactly the CLI: \(call)")
        }
    }
}

@Suite("Automation permission recovered from a failed command")
struct AutomationFailureTests {
    @Test("a permission error in command output becomes an actionable row")
    func refusalBecomesRow() {
        // The real shape of what `hide` prints when osascript is not allowed.
        let output = """
            hide: Spotify did not answer AppleScript within 10s
            execution error: Not authorized to send Apple events to «application Spotify». (-1743)
            """
        let state = Automation.failureState(output: output)
        #expect(state == .refused)
        let items = MenuBarModel.menuItems(version: "1.0", message: Automation.blockedMessage, automation: state!)
        #expect(items.count == 7, "name, sep, permission, toggle, message, sep, quit")
        #expect(items[2].title == Automation.blockedTitle)
        #expect(!items[2].isEnabled)
    }

    @Test("a -1744 failure offers the clickable grant row")
    func needsGrantBecomesClickableRow() {
        let state = Automation.failureState(output: "execution error: (-1744)")
        #expect(state == .needsGrant)
        let items = MenuBarModel.menuItems(version: "1.0", automation: state!)
        #expect(items[2].isPermissionRequest)
        #expect(items[2].isEnabled, "the OS will still prompt, so the click must work")
    }

    @Test("an ordinary failure is not blamed on permissions")
    func ordinaryFailureIsNotAPermissionProblem() {
        #expect(Automation.failureState(output: "hide: plist is not writable") == nil)
        #expect(Automation.failureState(output: "Spotify is not installed") == nil)
        #expect(Automation.failureState(output: "") == nil)
    }

    @Test("Spotify not running is not blamed on permissions either")
    func targetNotRunningIsNotAPermissionProblem() {
        // -600 must not raise a row: there is no grant to make.
        #expect(Automation.failureState(output: "Can't get application \"Spotify\". (-600)") == nil)
    }
}
