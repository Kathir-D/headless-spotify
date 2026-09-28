// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Entry point. Thin by design: parse errors exit 2, everything else runs
// through Runner (async so AppKit hops stay correct).

import Foundation

let argv = CommandLine.arguments
switch CLI.parse(argv) {
case .failure(let error):
    switch error {
    case .unknownSubcommand(let name):
        fputs("headless-spotify: unknown subcommand '\(name)'\n", stderr)
        fputs("Try 'headless-spotify --help'.\n", stderr)
    case .missingValue(let flag):
        fputs("headless-spotify: \(flag) needs a value\n", stderr)
    case .invalidValue(let flag, let value):
        fputs("headless-spotify: invalid value '\(value)' for \(flag)\n", stderr)
    }
    exit(2)
case .success(let invocation):
    let code = await Runner.run(invocation)
    exit(code)
}
