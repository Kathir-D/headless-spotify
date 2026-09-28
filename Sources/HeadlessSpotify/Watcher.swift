// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Watcher: the persistence half of task 3. Detects Dock-return and Spotify
// self-updates, then re-applies hiding. Pure decision logic (testable) +
// thin async loop (side effects).

import Foundation

/// What one watcher pass should do.
public enum WatchAction: Sendable, Equatable {
    /// Steady state: headless + scriptable, or Spotify not running (leave it).
    case none
    /// Plist says headless but Dock is back (stale launch): quit + relaunch headless.
    case relaunchHeadless(reason: String)
    /// LSUIElement was wiped (Spotify update) or never set: redo plist + resign + relaunch.
    case reapplyPlist(reason: String)
    /// Plist mode verified but Dock survives: try the injector dylib.
    case injectorFallback(reason: String)
}

public enum Watcher: Sendable {
    /// Decide from one status snapshot. `lastSeenVersion` is the app version
    /// from the previous pass (nil on the first pass); `plistFailures` counts
    /// consecutive passes where plist mode was correct yet the Dock stayed
    /// visible — that is the injector trigger.
    public static func decide(
        report: Runner.StatusReport,
        lastSeenVersion: String?,
        currentVersion: String?,
        plistFailures: Int
    ) -> WatchAction {
        guard report.installed else { return .none }
        guard report.running else { return .none } // don't launch Spotify unasked
        if let current = currentVersion, let last = lastSeenVersion, current != last {
            return .reapplyPlist(reason: "Spotify updated (\(last) → \(current)); re-applying LSUIElement")
        }
        if report.lsuiElement != true {
            return .reapplyPlist(reason: "LSUIElement missing (wiped by update?)")
        }
        switch report.dock {
        case .hidden:
            return report.isScriptable ? .none : .relaunchHeadless(reason: "headless but not answering AppleScript")
        case .visible:
            if plistFailures >= 1 {
                return .injectorFallback(reason: "Dock visible despite LSUIElement after relaunch")
            }
            return .relaunchHeadless(reason: "Dock visible despite LSUIElement (stale launch)")
        case .prohibited:
            return .relaunchHeadless(reason: "prohibited activation policy (unexpected)")
        case .notRunning:
            return .none
        }
    }

    /// Exponential backoff between passes, doubling per consecutive failure up
    /// to `maxMultiplier`. A Spotify build that refuses to be hidden (see README
    /// "Current status") would otherwise make every pass quit + relaunch +
    /// deep re-sign — a busy loop. Pure so it is easy to test.
    public static func backoffInterval(
        base: TimeInterval,
        failures: Int,
        maxMultiplier: Int = 16
    ) -> TimeInterval {
        guard base > 0, failures > 0 else { return max(base, 0) }
        let multiplier = 1 << min(max(failures, 0), 10)
        return base * TimeInterval(min(multiplier, max(maxMultiplier, 1)))
    }
}
