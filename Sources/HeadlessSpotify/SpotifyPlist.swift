// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Pure-Foundation plist management for the LSUIElement trick.
// Concept credit: 4ian/hide-spotify-from-dock (MIT) — see THIRD-PARTY-NOTICES.md.
//
// Backup covers BOTH Info.plist and _CodeSignature/CodeResources: ad-hoc
// re-signing (required on Apple Silicon after editing the plist) rewrites
// CodeResources, so restoring both files brings back Spotify's original
// Apple signature byte-for-byte.

import Foundation

public enum PlistError: Error, Sendable, Equatable {
    case appNotFound(String)
    case infoPlistMissing(String)
    case infoPlistUnreadable(String)
    case backupMissing(String)
    case notWritable(String)
}

public struct SpotifyPlist: Sendable {
    public let appPath: String

    public init(appPath: String) {
        self.appPath = appPath
    }

    public var infoPlistURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
    }

    public var backupURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist.headless-spotify-backup")
    }

    public var codeResourcesURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/_CodeSignature/CodeResources")
    }

    public var codeResourcesBackupURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/_CodeSignature/CodeResources.headless-spotify-backup")
    }

    public var appExists: Bool {
        FileManager.default.fileExists(atPath: appPath)
    }

    public var plistExists: Bool {
        FileManager.default.fileExists(atPath: infoPlistURL.path)
    }

    public var hasBackup: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    /// Writable by this process? hide/restore need this; otherwise advise sudo ./install.sh.
    public var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: infoPlistURL.path)
    }

    /// Current LSUIElement value. nil = key absent (normal Dock mode).
    public func readLSUIElement() throws -> Bool? {
        guard appExists else { throw PlistError.appNotFound(appPath) }
        guard plistExists else { throw PlistError.infoPlistMissing(infoPlistURL.path) }
        let data: Data
        do {
            data = try Data(contentsOf: infoPlistURL)
        } catch {
            throw PlistError.infoPlistUnreadable(infoPlistURL.path)
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: &format)
        } catch {
            throw PlistError.infoPlistUnreadable(infoPlistURL.path)
        }
        guard let dict = plist as? [String: Any] else {
            throw PlistError.infoPlistUnreadable(infoPlistURL.path)
        }
        return dict["LSUIElement"] as? Bool
    }

    /// Back up Info.plist (+ CodeResources when present). Keeps an existing
    /// backup untouched so the ORIGINAL is always what restore returns.
    public func backup() throws {
        guard appExists else { throw PlistError.appNotFound(appPath) }
        guard plistExists else { throw PlistError.infoPlistMissing(infoPlistURL.path) }
        let fm = FileManager.default
        if !hasBackup {
            try fm.copyItem(at: infoPlistURL, to: backupURL)
        }
        if fm.fileExists(atPath: codeResourcesURL.path),
           !fm.fileExists(atPath: codeResourcesBackupURL.path)
        {
            try fm.copyItem(at: codeResourcesURL, to: codeResourcesBackupURL)
        }
    }

    /// Set LSUIElement (true hides Dock+Cmd-Tab; false/nil restores normal mode).
    /// Backs up first when `backupFirst` (default true).
    public func setLSUIElement(_ value: Bool?, backupFirst: Bool = true) throws {
        if backupFirst { try backup() }
        let data = try Data(contentsOf: infoPlistURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var dict = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any] else {
            throw PlistError.infoPlistUnreadable(infoPlistURL.path)
        }
        if let value {
            dict["LSUIElement"] = value
        } else {
            dict.removeValue(forKey: "LSUIElement")
        }
        let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try out.write(to: infoPlistURL, options: .atomic)
    }

    /// Restore the backup over Info.plist (+ CodeResources) and remove backups,
    /// leaving the bundle exactly as before hide.
    public func restore() throws {
        guard hasBackup else { throw PlistError.backupMissing(backupURL.path) }
        let fm = FileManager.default
        // Remove live files first so copyItem can't fail on existing destination.
        if fm.fileExists(atPath: infoPlistURL.path) {
            try fm.removeItem(at: infoPlistURL)
        }
        try fm.copyItem(at: backupURL, to: infoPlistURL)
        try fm.removeItem(at: backupURL)
        if fm.fileExists(atPath: codeResourcesBackupURL.path) {
            if fm.fileExists(atPath: codeResourcesURL.path) {
                try fm.removeItem(at: codeResourcesURL)
            }
            try fm.copyItem(at: codeResourcesBackupURL, to: codeResourcesURL)
            try fm.removeItem(at: codeResourcesBackupURL)
        }
    }
}
