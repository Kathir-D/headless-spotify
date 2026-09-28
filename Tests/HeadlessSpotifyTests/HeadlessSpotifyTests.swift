import Testing

@testable import HeadlessSpotify

@Suite("CLI parsing (task 1 stubs)")
struct CLITests {
    @Test("bare invocation shows help")
    func bareShowsHelp() {
        let result = CLI.parse(["headless-spotify"])
        #expect(result == .success(Invocation(subcommand: nil, showHelp: true)))
    }

    @Test("--help flag")
    func helpFlag() throws {
        for flag in ["-h", "--help"] {
            let result = CLI.parse(["headless-spotify", flag])
            #expect(try result.get().showHelp == true)
        }
    }

    @Test("subcommands parse", arguments: ["status", "hide", "restore"])
    func subcommandsParse(name: String) throws {
        let result = CLI.parse(["headless-spotify", name])
        #expect(try result.get().subcommand == Subcommand(rawValue: name))
    }

    @Test("unknown subcommand errors")
    func unknownErrors() {
        let result = CLI.parse(["headless-spotify", "cloak"])
        #expect(result == .failure(.unknownSubcommand("cloak")))
    }

    @Test("--spotify-app override")
    func appPathOverride() throws {
        let custom = "/Volumes/Music/Spotify.app"
        let r1 = CLI.parse(["headless-spotify", "--spotify-app", custom, "status"])
        #expect(try r1.get().spotifyAppPath == custom)
        let r2 = CLI.parse(["headless-spotify", "--spotify-app=\(custom)", "hide"])
        #expect(try r2.get().spotifyAppPath == custom)
    }

    @Test("help text mentions contract")
    func helpMentionsContract() {
        #expect(CLI.helpText.contains("com.spotify.client"))
        #expect(CLI.helpText.contains("status|hide|restore"))
    }

    @Test("run stubs exit 0", arguments: ["status", "hide", "restore"])
    func runStubsExitZero(name: String) {
        let invocation = Invocation(subcommand: Subcommand(rawValue: name))
        var lines: [String] = []
        let code = CLI.run(invocation) { lines.append($0) }
        #expect(code == 0)
        #expect(!lines.isEmpty)
    }
}
