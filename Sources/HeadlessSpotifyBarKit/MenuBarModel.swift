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
    case quit
}

/// One row in the menu bar menu.
public struct MenuItemSpec: Sendable, Equatable {
    /// Display text (ignored for separators).
    public var title: String
    public var isSeparator: Bool
    /// false = informational row (greyed out, not clickable).
    public var isEnabled: Bool
    public var action: MenuAction

    public init(
        title: String,
        isSeparator: Bool = false,
        isEnabled: Bool = true,
        action: MenuAction = .none
    ) {
        self.title = title
        self.isSeparator = isSeparator
        self.isEnabled = isEnabled
        self.action = action
    }

    public var isQuit: Bool { action == .quit }
    public var isToggle: Bool { action == .toggleHiding }
}

public enum MenuBarModel: Sendable {
    /// Shown in the menu and used as the status item's tooltip.
    public static let projectName = "headless-spotify"
    /// SF Symbol drawn in the menu bar (template image, tints with the menu bar).
    public static let iconSymbolName = "waveform"
    public static let quitTitle = "Quit \(projectName)"
    public static let disableTitle = "Disable hiding"
    public static let enableTitle = "Enable hiding"
    public static let busyTitle = "Working…"
    public static let cliMissingTitle = "\(projectName) CLI not found"

    /// Toggle label for the current state.
    public static func toggleTitle(hidingEnabled: Bool) -> String {
        hidingEnabled ? disableTitle : enableTitle
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
    public static func menuItems(
        version: String,
        hidingEnabled: Bool = false,
        cliAvailable: Bool = true,
        busy: Bool = false,
        message: String? = nil
    ) -> [MenuItemSpec] {
        let toggle: MenuItemSpec
        if !cliAvailable {
            toggle = MenuItemSpec(title: cliMissingTitle, isEnabled: false)
        } else if busy {
            toggle = MenuItemSpec(title: busyTitle, isEnabled: false)
        } else {
            toggle = MenuItemSpec(
                title: toggleTitle(hidingEnabled: hidingEnabled),
                action: .toggleHiding
            )
        }
        var items: [MenuItemSpec] = [
            MenuItemSpec(title: "\(projectName) \(version)", isEnabled: false),
            MenuItemSpec(title: "", isSeparator: true, isEnabled: false),
            toggle,
        ]
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

// MARK: - Toggle command plan

/// Which way the toggle goes.
public enum ToggleAction: Sendable, Equatable {
    case enable
    case disable

    /// CLI subcommand for this direction.
    public var subcommand: String {
        self == .enable ? "hide" : "restore"
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
