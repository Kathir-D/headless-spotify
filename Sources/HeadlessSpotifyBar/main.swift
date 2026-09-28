// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Entry point for the menu bar extra. NSStatusItem + a menu built from
// MenuBarModel, then the AppKit event loop.
//
// The Enable/Disable row does not reimplement hiding: it drives the existing
// `headless-spotify` binary (hide/restore), which is the single source of
// truth. Toggling runs off the main thread because hiding re-signs the bundle
// and waits for AppleScript — that can take minutes.
//
// This binary is packaged as an LSUIElement .app (see
// scripts/build-menubar.sh) so it has no Dock icon and no Cmd-Tab entry —
// the same trick this project applies to Spotify. It needs no special
// permission: menu bar extras are always allowed.

import AppKit
import Foundation

import HeadlessSpotifyBarKit

// MARK: - Configuration

let environment = ProcessInfo.processInfo.environment
// Version comes from the app bundle's Info.plist (written at build time from
// the VERSION file). Unbundled runs (--print-menu-spec) report "dev".
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let spotifyAppPath = environment["HEADLESS_SPOTIFY_APP"] ?? "/Applications/Spotify.app"
let infoPlistURL = URL(fileURLWithPath: spotifyAppPath).appendingPathComponent("Contents/Info.plist")

/// Is hiding configured right now? `LSUIElement` is the persistent state the
/// toggle flips; it is readable even while Spotify is not running.
func currentHidingState() -> Bool {
    guard let data = try? Data(contentsOf: infoPlistURL) else { return false }
    return HidingState.hidingEnabled(plistData: data)
}

func cliPath() -> String? {
    CLILocator.resolve(
        env: environment,
        barExecutablePath: CommandLine.arguments.first,
        exists: { FileManager.default.isExecutableFile(atPath: $0) }
    )
}

// MARK: - Menu controller

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let menu = NSMenu()
    private var cli: String?
    private var isBusy = false
    private var message: String?

    func attach(to statusItem: NSStatusItem) {
        menu.delegate = self
        rebuild()
        statusItem.menu = menu
    }

    /// Recompute state every time the menu opens, so the label always reflects
    /// reality (including changes made from the terminal or the watcher).
    func menuWillOpen(_ menu: NSMenu) {
        cli = cliPath()
        message = nil
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        for spec in MenuBarModel.menuItems(
            version: appVersion,
            hidingEnabled: currentHidingState(),
            cliAvailable: cli != nil,
            busy: isBusy,
            message: message
        ) {
            if spec.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
            switch spec.action {
            case .none:
                break
            case .toggleHiding:
                item.action = #selector(toggleHiding(_:))
                item.target = self
            case .quit:
                item.action = #selector(NSApplication.terminate(_:))
                item.target = NSApp
                item.keyEquivalent = "q"
            }
            item.isEnabled = spec.isEnabled
            menu.addItem(item)
        }
    }

    @objc private func toggleHiding(_ sender: Any?) {
        guard !isBusy, let cli else { return }
        let action: ToggleAction = currentHidingState() ? .disable : .enable
        isBusy = true
        message = nil
        rebuild()
        let plan = TogglePlan.commands(
            action: action,
            cliPath: cli,
            spotifyAppPath: spotifyAppPath,
            bundleWritable: FileManager.default.isWritableFile(atPath: infoPlistURL.path)
        )
        let elevate = plan.count > 1
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if elevate {
                // Bring the password dialog to the front: an LSUIElement app
                // has no Dock icon to click.
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
            }
            let result = Self.run(plan)
            DispatchQueue.main.async {
                self?.isBusy = false
                self?.message = result.succeeded ? nil : MenuBarModel.statusMessage(result.output)
                self?.rebuild()
            }
        }
    }

    /// Run commands in order, stopping at the first failure.
    nonisolated static func run(_ commands: [CommandSpec]) -> (succeeded: Bool, output: String) {
        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (false, "could not run \(command.executable): \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                return (false, text)
            }
        }
        return (true, "")
    }
}

// MARK: - Entry point

// `--print-menu-spec` mirrors `watch --print-agent-plist`: a hermetic,
// GUI-free view of the menu, used by scripts/smoke-test.sh. It reflects the
// live state (read-only) unless the state is pinned with --hiding-enabled /
// --hiding-disabled, which keeps the output deterministic.
if CommandLine.arguments.contains("--print-menu-spec") {
    let pinnedEnabled = CommandLine.arguments.contains("--hiding-enabled")
    let pinnedDisabled = CommandLine.arguments.contains("--hiding-disabled")
    let enabled = (pinnedEnabled || pinnedDisabled) ? pinnedEnabled : currentHidingState()
    let cli = cliPath()
    for item in MenuBarModel.menuItems(version: appVersion, hidingEnabled: enabled, cliAvailable: cli != nil) {
        if item.isSeparator {
            print("---")
        } else {
            let suffix = item.isEnabled ? "" : "  (informational)"
            print("\(item.title)\(suffix)")
        }
    }
    exit(0)
}

for argument in CommandLine.arguments.dropFirst() where argument.hasPrefix("-") {
    FileHandle.standardError.write(
        Data("headless-spotify-bar: unknown option '\(argument)'\n".utf8)
    )
    FileHandle.standardError.write(Data("Try 'headless-spotify-bar --print-menu-spec'.\n".utf8))
    exit(2)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let button = statusItem.button {
    let image = NSImage(
        systemSymbolName: MenuBarModel.iconSymbolName,
        accessibilityDescription: MenuBarModel.projectName
    )
    image?.isTemplate = true
    button.image = image
    button.toolTip = MenuBarModel.projectName
}

MenuController().attach(to: statusItem)

application.run()
