// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Menu bar extra model: the pure description of the top-bar button, its menu,
// and the commands behind the Enable/Disable toggle. No AppKit here, so all of
// it stays unit-testable; the AppKit glue (NSStatusItem + NSMenu + process
// spawning) lives in HeadlessSpotifyBar/main.swift.
//
// The menu drives the existing CLI instead of reimplementing hide/restore, so
// the menu can never disagree with `headless-spotify` itself.

import Foundation

/// What a menu row does when clicked.
public enum MenuAction: Sendable, Equatable {
    /// Informational row.
    case none
    /// Enable hiding if it is off, disable it if it is on.
    case toggleHiding
    /// Ask macOS for permission to control Spotify. Sending the Apple Event is
    /// what makes the system prompt appear.
    case requestAutomation
    case quit
}

/// Checkmark state of a menu row, so a toggle shows *what is true now*
/// rather than only what a click would do.
public enum MenuItemState: Sendable, Equatable {
    case none
    case on
    case off
}

/// One row in the menu bar menu.
public struct MenuItemSpec: Sendable, Equatable {
    /// Display text (ignored for separators).
    public var title: String
    public var isSeparator: Bool
    /// false = informational row (greyed out, not clickable).
    public var isEnabled: Bool
    public var action: MenuAction
    public var state: MenuItemState

    public init(
        title: String,
        isSeparator: Bool = false,
        isEnabled: Bool = true,
        action: MenuAction = .none,
        state: MenuItemState = .none
    ) {
        self.title = title
        self.isSeparator = isSeparator
        self.isEnabled = isEnabled
        self.action = action
        self.state = state
    }

    public var isQuit: Bool { action == .quit }
    public var isToggle: Bool { action == .toggleHiding }
    public var isPermissionRequest: Bool { action == .requestAutomation }
}

public enum MenuBarModel: Sendable {
    /// Shown in the menu and used as the status item's tooltip.
    public static let projectName = "headless-spotify"
    /// Menu bar icon while Spotify is hidden from the Dock.
    public static let hiddenIconSymbolName = "eye.slash"
    /// Menu bar icon while Spotify is visible in the Dock.
    public static let visibleIconSymbolName = "music.note"
    public static let quitTitle = "Quit \(projectName)"
    /// The row states what is true now, not what clicking would do.
    public static let toggleTitle = "Hidden from Dock"
    public static let busyTitle = "Working…"
    public static let cliMissingTitle = "\(projectName) CLI not found"

    /// The permission row, when there is something to say.
    ///
    /// `.unknown` deliberately produces no row. It is the sub-second state
    /// before the first probe, and a row that appears and then changes under the
    /// user's cursor is worse than one that is briefly absent.
    public static func permissionTitle(for state: AutomationState) -> String? {
        switch state {
        case .unknown, .granted: return nil
        case .needsGrant: return Automation.permissionTitle
        case .refused: return Automation.blockedTitle
        }
    }

    /// Icon for the current state, so the top bar shows it without opening
    /// the menu. A missing symbol falls back to the text title in the glue.
    public static func iconSymbolName(hidingEnabled: Bool) -> String {
        hidingEnabled ? hiddenIconSymbolName : visibleIconSymbolName
    }

    /// Tooltip for the current state.
    public static func tooltip(hidingEnabled: Bool) -> String {
        hidingEnabled
            ? "\(projectName): Spotify is hidden from the Dock"
            : "\(projectName): Spotify shows in the Dock"
    }

    /// One short line from a CLI result, for the informational status row.
    /// nil when there is nothing worth showing.
    public static func statusMessage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let firstLine = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !firstLine.isEmpty else { return nil }
        let limit = 60
        if firstLine.count <= limit { return firstLine }
        return String(firstLine.prefix(limit - 1)) + "…"
    }

    /// Menu rows: project name, separator, Enable/Disable, separator, Quit.
    /// - Parameters:
    ///   - hidingEnabled: LSUIElement currently set on the Spotify bundle.
    ///   - cliAvailable: a `headless-spotify` binary was found to drive.
    ///   - busy: a toggle is already running; the row is disabled meanwhile.
    ///   - message: optional one-line result from the last toggle.
    ///   - automation: whether this app may control Spotify yet.
    public static func menuItems(
        version: String,
        hidingEnabled: Bool = false,
        cliAvailable: Bool = true,
        busy: Bool = false,
        message: String? = nil,
        automation: AutomationState = .unknown
    ) -> [MenuItemSpec] {
        let toggle: MenuItemSpec
        if !cliAvailable {
            toggle = MenuItemSpec(title: cliMissingTitle, isEnabled: false)
        } else if busy {
            toggle = MenuItemSpec(
                title: busyTitle,
                isEnabled: false,
                state: hidingEnabled ? .on : .off
            )
        } else {
            toggle = MenuItemSpec(
                title: toggleTitle,
                action: .toggleHiding,
                state: hidingEnabled ? .on : .off
            )
        }
        var items: [MenuItemSpec] = [
            MenuItemSpec(title: "\(projectName) \(version)", isEnabled: false),
            MenuItemSpec(title: "", isSeparator: true, isEnabled: false),
        ]
        // Above the toggle, not below it. A missing permission makes the toggle
        // do nothing, so burying the explanation under the thing that does
        // nothing is how this gets missed.
        if let title = permissionTitle(for: automation) {
            items.append(
                MenuItemSpec(
                    title: title,
                    // A refused permission has no button that can work; sending
                    // the event would silently do nothing, which is the exact
                    // confusion this row exists to remove.
                    isEnabled: automation.canPrompt,
                    action: automation.canPrompt ? .requestAutomation : .none
                )
            )
        }
        items.append(toggle)
        if let message {
            items.append(MenuItemSpec(title: message, isEnabled: false))
        }
        items.append(MenuItemSpec(title: "", isSeparator: true, isEnabled: false))
        items.append(MenuItemSpec(title: quitTitle, action: .quit))
        return items
    }
}

// MARK: - Hiding state probe

/// Reads whether hiding is configured from raw `Info.plist` bytes. Pure so the
/// menu bar's toggle and the CLI cannot disagree about "is hiding on?".
public enum HidingState: Sendable {
    public static func hidingEnabled(plistData: Data) -> Bool {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: &format),
              let dict = plist as? [String: Any],
              let value = dict["LSUIElement"] as? Bool
        else { return false }
        return value
    }
}

// MARK: - Locating the CLI

/// Finds the `headless-spotify` binary that the toggle drives. The bar app is
/// a separate bundle (usually in /Applications), so the binary lives
/// elsewhere: an env override wins, then the install prefixes, then anything
/// sitting next to the running bar binary (tarball/dev layouts).
public enum CLILocator: Sendable {
    public static let binaryName = "headless-spotify"
    public static let envOverride = "HEADLESS_CLI"

    public static func candidates(
        env: [String: String] = [:],
        barExecutablePath: String? = nil
    ) -> [String] {
        var paths: [String] = []
        if let override = env[envOverride], !override.isEmpty {
            paths.append(override)
        }
        paths.append("/usr/local/bin/\(binaryName)")
        paths.append("/opt/homebrew/bin/\(binaryName)")
        // Intel Homebrew, which many iMac/MacBook installs still use.
        paths.append("/home/linuxbrew/.linuxbrew/bin/\(binaryName)")
        if let bar = barExecutablePath, !bar.isEmpty {
            let dir = URL(fileURLWithPath: bar).deletingLastPathComponent()
            paths.append(dir.appendingPathComponent(binaryName).standardized.path)
            paths.append(dir.appendingPathComponent("../bin/\(binaryName)").standardized.path)
        }
        // De-duplicate while preserving priority order.
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// First candidate that exists, or nil.
    public static func resolve(
        env: [String: String] = [:],
        barExecutablePath: String? = nil,
        exists: (String) -> Bool
    ) -> String? {
        candidates(env: env, barExecutablePath: barExecutablePath).first(where: exists)
    }
}

// MARK: - Automation permission

/// Whether this app is allowed to send Apple Events to Spotify.
///
/// Every control path in this project runs `osascript`, and the *responsible
/// process* for a TCC check is whatever launched the script. Run from a
/// terminal, that is the terminal. Run from this menu bar extra, it is this app
/// — so this app needs its own grant, and the user's terminal having one does
/// nothing for it.
///
/// The failure without a grant is quiet and confusing: the CLI runs, exits
/// non-zero with an AppleScript error on stderr, and the menu shows that
/// message. Nothing says "you need to allow this app to control Spotify",
/// because macOS only ever prompts when something actually asks — and the one
/// thing that asks is a real Apple Event, which we deliberately did not send
/// from a background timer. So the app asks the user instead, through a menu
/// row, and the click is what sends the event.
public enum AutomationState: Sendable, Equatable {
    /// Not read yet.
    case unknown
    /// Allowed.
    case granted
    /// Never asked, so the OS will still prompt on the next real event.
    case needsGrant
    /// Refused, or otherwise blocked: the OS will not prompt again, and only
    /// System Settings can change it.
    case refused

    public var isGranted: Bool { self == .granted }
    /// True when asking again can still do something.
    public var canPrompt: Bool { self == .needsGrant }
}

/// The Apple Event half of the permission, kept here so the state machine is
/// testable and the spawning stays in one place.
public enum Automation: Sendable {
    public static let osascript = "/usr/bin/osascript"
    public static let spotifyBundleID = "com.spotify.client"
    /// Reads one property and nothing else. It is the cheapest Apple Event
    /// available, it is the same call the CLI makes, and using the same call is
    /// the point: a permission probe that asked a *different* question could
    /// disagree with the command that then fails.
    public static let probeScript = "tell application \"Spotify\" to get player state"
    public static let permissionTitle = "Allow control of Spotify"
    public static let blockedTitle = "Control of Spotify is blocked"
    public static let permissionMessage =
        "headless-spotify needs permission to control Spotify so it can read what is playing. "
            + "macOS will ask. Choose OK."
    public static let blockedMessage =
        "macOS will not ask again. Turn it on in System Settings › Privacy & Security › Automation."

    /// Map what `osascript` reported to a state.
    ///
    /// The numbers are the OSStatus values Apple puts in the script error
    /// message, and they are matched as numbers rather than prose because the
    /// prose is localised and the numbers are not.
    ///
    /// The fallbacks differ from `classify` on purpose. A probe that failed for
    /// a reason we do not recognise has learned *nothing*, so it reads as
    /// `.unknown` and shows no row; reading it as `.granted` would hide a real
    /// missing grant, and reading it as `.refused` would send a user to System
    /// Settings for a permission that was never refused.
    public static func state(exitCode: Int32, standardError: String) -> AutomationState {
        guard exitCode != 0 else { return .granted }
        return classify(standardError) ?? .unknown
    }

    /// The permission a piece of output implicates, or nil when it implicates
    /// none.
    ///
    /// This is the backstop the probe cannot be. Apple Events are checked
    /// against the *responsible process* and inherit down the process chain, so
    /// a probe spawned from an app that was itself launched from an
    /// already-authorised terminal succeeds whether or not the app itself holds
    /// a grant — measured on this machine, which is why a live prompt could not
    /// be provoked here. When a real command does fail on the permission, its
    /// own output is the trustworthy evidence, and without this the user gets a
    /// raw `(-1743)` line and no idea what to do about it.
    public static func classify(_ output: String) -> AutomationState? {
        if output.contains("-1743") { return .refused }
        // -1744: the OS would prompt, so a click can still fix it.
        if output.contains("-1744") { return .needsGrant }
        // -600: Spotify is not running. There is no grant to make yet, which is
        // not a permission problem and must not be shown as one.
        if output.contains("-600") { return nil }
        return nil
    }

    /// The permission state a failed command implies, or nil when the failure
    /// was something else entirely.
    public static func failureState(output: String) -> AutomationState? {
        classify(output)
    }
}

// MARK: - Gatekeeper quarantine

/// Removal of `com.apple.quarantine` from the CLI the toggle drives.
///
/// This exists because of a bug that made the Enable/Disable row look broken.
/// The Homebrew cask's postflight cleared the quarantine attribute from the
/// .app but not from the Caskroom copy of the CLI that its `binary` stanza
/// links into the Homebrew prefix, so that binary stayed quarantined. A menu
/// bar extra is a GUI process, and a GUI process exec'ing a quarantined binary
/// is the case that trips Gatekeeper's assessment: dyld blocks inside
/// `_dyld_start`, CoreServicesUIAgent puts up "Apple could not verify
/// "headless-spotify" is free of malware", and the toggle never returns. The
/// same binary run from a terminal prompts for nothing, which is why nothing
/// caught it.
///
/// The cask now clears the Caskroom too, but that only helps installs that
/// happen after the fix. Somebody who already has the app on disk — and
/// everybody who upgrades in place — still has a quarantined CLI, and the
/// symptom is a menu that silently does nothing. So the app repairs it itself
/// before it runs anything.
///
/// Clearing the attribute is the same decision the cask already makes, on the
/// same file, for the same reason: `brew install` verified a SHA-256 over this
/// exact tarball before any of it was unpacked. It is also why this only ever
/// touches the single file it is about to execute, and why it is a no-op when
/// there is nothing to clear.
public enum Quarantine: Sendable {
    public static let attribute = "com.apple.quarantine"
    public static let xattr = "/usr/bin/xattr"
    /// The recursive-delete form, which is what makes one call enough.
    public static let recursiveDelete = ["-dr"]

    /// A command to run, so the whole thing is testable without touching the
    /// filesystem. Mirrors `SpotifyScripting.Runner`, but kept local so this
    /// target stays free of a dependency on the CLI target.
    public typealias Runner = @Sendable (String, [String]) async -> Int32

    /// Strip the attribute from `path` if it is there. Returns true when the
    /// path is clear afterwards, whether or not anything had to be removed.
    ///
    /// Only the file itself is touched, never a parent directory. The Caskroom
    /// copy is user-owned, so this needs no privileges, and the narrow scope
    /// means a mistaken path cannot strip quarantine from something unrelated.
    @discardableResult
    public static func clearIfNeeded(at path: String, run: Runner) async -> Bool {
        guard !path.isEmpty else { return false }
        guard await isQuarantined(path, run: run) else { return true }
        _ = await run(xattr, recursiveDelete + [attribute, path])
        // Re-probed rather than assuming the delete worked: xattr's exit code
        // is the only answer available, and a file the user cannot write fails
        // silently. Returning `isQuarantined` here would report that failure as
        // success, which is the one thing the caller uses this for.
        return !(await isQuarantined(path, run: run))
    }

    /// True when `xattr -p` reports the attribute on `path`.
    ///
    /// `xattr -p` exits 0 when the attribute is there and non-zero when it is
    /// not, so the exit code is the whole answer. Nothing is parsed, which also
    /// means a path that does not exist reads as "not quarantined" — the right
    /// answer, since there is then nothing to clear.
    public static func isQuarantined(_ path: String, run: Runner) async -> Bool {
        await run("/usr/bin/xattr", ["-p", attribute, path]) == 0
    }
}

/// Which way the toggle goes.
public enum ToggleAction: Sendable, Equatable {
    case enable
    case disable

    /// CLI subcommand for this direction.
    public var subcommand: String {
        self == .enable ? "hide" : "restore"
    }

    /// The direction a toggle click should go, given the current state.
    public init(hidingEnabled: Bool) {
        self = hidingEnabled ? .disable : .enable
    }
}

/// A process to run. Pure data so the plan is unit-testable.
public struct CommandSpec: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum TogglePlan: Sendable {
    public static let osascript = "/usr/bin/osascript"

    /// Commands to run, in order, for one toggle.
    ///
    /// Writable bundle: a single `hide`/`restore` as the user. Not writable
    /// (the usual root-owned /Applications copy): the plist edit needs root,
    /// so it runs through one administrator prompt and the relaunch still
    /// happens as the user — the same split `install.sh` uses, because
    /// launching Spotify as root would give it the wrong session.
    public static func commands(
        action: ToggleAction,
        cliPath: String,
        spotifyAppPath: String,
        bundleWritable: Bool
    ) -> [CommandSpec] {
        let app = ["--spotify-app", spotifyAppPath]
        if bundleWritable {
            return [CommandSpec(executable: cliPath, arguments: [action.subcommand] + app)]
        }
        return [
            CommandSpec(
                executable: osascript,
                arguments: ["-e", elevatedScript(cliPath: cliPath, arguments: [action.subcommand, "--skip-relaunch"] + app)]
            ),
            CommandSpec(executable: cliPath, arguments: [action.subcommand, "--skip-plist"] + app),
        ]
    }

    /// `do shell script "…" with administrator privileges` for the root half.
    public static func elevatedScript(cliPath: String, arguments: [String]) -> String {
        let command = ([cliPath] + arguments).map(shellQuote).joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// POSIX single-quote quoting, so paths with spaces stay one argument.
    public static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
