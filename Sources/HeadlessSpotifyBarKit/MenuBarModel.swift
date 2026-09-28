// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Menu bar extra model: the pure description of the top-bar button and its
// menu. No AppKit here, so the menu contents stay unit-testable; the AppKit
// glue (NSStatusItem + NSMenu) lives in HeadlessSpotifyBar/main.swift.
//
// The menu is deliberately minimal: the project name (informational) and a
// single Quit action. Everything else stays CLI-driven on purpose — a status
// bar app that duplicated every subcommand would drift from the real
// behaviour of `headless-spotify`.

import Foundation

/// One row in the menu bar menu.
public struct MenuItemSpec: Sendable, Equatable {
    /// Display text (ignored for separators).
    public var title: String
    public var isSeparator: Bool
    /// false = informational row (greyed out, not clickable).
    public var isEnabled: Bool
    /// The row wired to `NSApplication.terminate(_:)`.
    public var isQuit: Bool

    public init(title: String, isSeparator: Bool = false, isEnabled: Bool = true, isQuit: Bool = false) {
        self.title = title
        self.isSeparator = isSeparator
        self.isEnabled = isEnabled
        self.isQuit = isQuit
    }
}

public enum MenuBarModel: Sendable {
    /// Shown in the menu and used as the status item's tooltip.
    public static let projectName = "headless-spotify"
    /// SF Symbol drawn in the menu bar (template image, tints with the menu bar).
    public static let iconSymbolName = "waveform"
    public static let quitTitle = "Quit \(projectName)"

    /// Menu rows, in order: project name, separator, Quit.
    public static func menuItems(version: String) -> [MenuItemSpec] {
        [
            MenuItemSpec(title: "\(projectName) \(version)", isEnabled: false),
            MenuItemSpec(title: "", isSeparator: true, isEnabled: false),
            MenuItemSpec(title: quitTitle, isQuit: true),
        ]
    }
}
