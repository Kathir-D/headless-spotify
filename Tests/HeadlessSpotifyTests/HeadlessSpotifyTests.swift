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

    @Test("subcommands parse", arguments: ["status", "hide", "restore", "watch"])
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

    @Test("watch stub exits 0")
    func watchStub() async {
        let lines = Lines()
        let code = await Runner.run(
            Invocation(subcommand: .watch),
            output: { lines.values.append($0) },
            errorOutput: { _ in }
        )
        #expect(code == 0)
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

@Suite("SpotifyScripting with stubbed runner")
struct ScriptingTests {
    final class Box: @unchecked Sendable {
        var calls: [String] = []
        var n = 0
    }

    @Test("not running short-circuits osascript")
    func notRunningShortCircuits() {
        let box = Box()
        let run: SpotifyScripting.Runner = { exe, args in
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
        let run: SpotifyScripting.Runner = { exe, _ in
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
