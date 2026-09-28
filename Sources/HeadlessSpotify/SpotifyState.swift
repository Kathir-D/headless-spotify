// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Main-thread AppKit access: running-app lookup, activationPolicy (the
// ground truth for "is the Dock icon gone?"), headless launch, terminate.
// Everything here is @MainActor and called via `await MainActor.run` so the
// rest of the CLI stays off the main thread.

import AppKit
import Foundation

/// Mirrors NSApplication.ActivationPolicy without leaking AppKit into callers.
public enum DockPresence: String, Sendable, Equatable {
    /// `.regular` — Dock icon + Cmd-Tab entry visible.
    case visible
    /// `.accessory` (LSUIElement / injector) — no Dock, no Cmd-Tab, windows work.
    case hidden
    /// `.prohibited` — no UI at all (unexpected for Spotify).
    case prohibited
    /// Spotify is not running.
    case notRunning

    public var isHeadless: Bool { self == .hidden }
}

@MainActor
public enum SpotifyState: Sendable {
    public static let bundleID = "com.spotify.client"

    public static func runningApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    public static func dockPresence() -> DockPresence {
        guard let app = runningApp() else { return .notRunning }
        switch app.activationPolicy {
        case .regular: return .visible
        case .accessory: return .hidden
        case .prohibited: return .prohibited
        @unknown default: return .visible
        }
    }

    /// Launch without activating (no Dock bounce, no focus steal).
    /// For an LSUIElement bundle this also means no Dock icon, ever.
    public static func launchHeadless(appPath: String) async throws -> Bool {
        let url = URL(fileURLWithPath: appPath)
        return try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.hides = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: app != nil)
                }
            }
        }
    }

    /// Normal (restoring) launch: activates so the user sees Spotify again.
    public static func launchNormal(appPath: String) async throws -> Bool {
        let url = URL(fileURLWithPath: appPath)
        return try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: app != nil)
                }
            }
        }
    }

    /// Ask Spotify to quit; wait up to `timeout` for it to exit.
    public static func terminate(timeout: TimeInterval = 8) async -> Bool {
        guard let app = runningApp() else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningApp() == nil { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return runningApp() == nil
    }
}
