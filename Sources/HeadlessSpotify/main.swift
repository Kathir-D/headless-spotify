// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Entry point. Kept thin so the test target can import the CLI model;
// real hide/restore logic lands in tasks 2–3.

import Foundation

let argv = CommandLine.arguments
let invocation: Invocation
switch CLI.parse(argv) {
case .success(let parsed):
    invocation = parsed
case .failure(let error):
    switch error {
    case .unknownSubcommand(let name):
        fputs("headless-spotify: unknown subcommand '\(name)'\n", stderr)
        fputs("Try 'headless-spotify --help'.\n", stderr)
    }
    exit(2)
}

let code = CLI.run(invocation)
exit(code)
