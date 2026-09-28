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
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.5)
                if process.isRunning {
                    // terminate() is polite; kill() is final (SIGKILL = 9).
                    kill(process.processIdentifier, 9)
                }
                return ProcessResult(exitCode: 124, stdout: "", stderr: "timed out after \(Int(timeout))s: \(executable) \(args.joined(separator: " "))", timedOut: true)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
