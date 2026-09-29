// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Thin synchronous process runner (osascript, codesign, pgrep). Kept in one
// place so scripting calls are mockable in tests via the `run` closure.

import Foundation

public struct ProcessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    /// True when the child was killed for exceeding `timeout` (exitCode 124).
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public enum ProcessRunner: Sendable {
    /// Run an executable synchronously, capturing output. No shell involved.
    /// `timeout` kills a hung child (exitCode 124) instead of blocking forever —
    /// osascript against a half-launched app can otherwise block indefinitely.
    public static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 60) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: 127, stdout: "", stderr: "\(error)")
        }

        // Drain both pipes concurrently while the child runs. Reading them
        // only after it exits deadlocks: a pipe holds ~64 KB, so a chatty
        // child (`codesign --deep`, a long osascript error) blocks in write()
        // and never exits. Partial output is still reported on timeout.
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        let collector = DispatchQueue(label: "headless-spotify.process-output", attributes: .concurrent)
        collector.async(group: group) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        collector.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline {
                timedOut = true
                process.terminate()
                Thread.sleep(forTimeInterval: 0.5)
                if process.isRunning {
                    // terminate() is polite; kill() is final (SIGKILL = 9).
                    kill(process.processIdentifier, 9)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // The readers finish once the write ends are closed.
        group.wait()
        if timedOut {
            return ProcessResult(
                exitCode: 124,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: "timed out after \(Int(timeout))s: \(executable) \(args.joined(separator: " "))",
                timedOut: true
            )
        }
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
