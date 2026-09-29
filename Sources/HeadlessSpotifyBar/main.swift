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

// MARK: - Running the CLI

/// Runs a short command and returns its exit code.
///
/// Deliberately not the main thread and with no output plumbing: the only
/// commands run through here are `xattr -p` and `xattr -dr`, which are
/// instantaneous, and the result is a single Int32.
private func runForExitCode(_ executable: String, _ arguments: [String]) async -> Int32 {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            // xattr prints the attribute's value on stdout. Discarding it keeps
            // a stray value out of the menu bar app's own output.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Int32(127))
                return
            }
            process.waitUntilExit()
            continuation.resume(returning: process.terminationStatus)
        }
    }
}

/// Strip Gatekeeper's quarantine attribute from the CLI, if it carries one.
///
/// See `Quarantine` in MenuBarModel for why this is here: a quarantined binary
/// launched by this GUI app hangs in dyld behind a "could not verify" alert,
/// and the toggle would appear to do nothing at all. An install that predates
/// the cask fix still has one, and the user cannot fix that without noticing
/// what is wrong.
///
/// Returns a short line for the menu when something actually had to be removed,
/// so the repair is visible rather than silent, and nil otherwise.
private func repairQuarantineIfNeeded(cli: String) async -> String? {
    guard await Quarantine.isQuarantined(cli, run: runForExitCode) else { return nil }
    guard await Quarantine.clearIfNeeded(at: cli, run: runForExitCode) else {
        return "Could not clear Gatekeeper quarantine; try reinstalling"
    }
    return "Cleared Gatekeeper quarantine on the CLI"
}

// MARK: - Menu controller

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let menu = NSMenu()
    private var cli: String?
    private var isBusy = false
    private var message: String?
    private weak var button: NSStatusBarButton?

    func attach(to statusItem: NSStatusItem) {
        menu.delegate = self
        button = statusItem.button
        rebuild()
        statusItem.menu = menu
    }

    /// Recompute state every time the menu opens, so the label and the icon
    /// always reflect reality (including changes made from the terminal or
    /// the watcher).
    func menuWillOpen(_ menu: NSMenu) {
        cli = cliPath()
        message = nil
        rebuild()
    }

    /// Keep the top-bar icon in step with the state, so hiding is visible
    /// without opening the menu.
    private func refreshIcon(hidingEnabled: Bool) {
        guard let button else { return }
        let symbol = MenuBarModel.iconSymbolName(hidingEnabled: hidingEnabled)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: MenuBarModel.projectName) {
            image.isTemplate = true
            button.image = image
        } else {
            // A missing SF Symbol must still show something recognisable.
            button.image = nil
            button.title = hidingEnabled ? "HS" : "S"
        }
        button.toolTip = MenuBarModel.tooltip(hidingEnabled: hidingEnabled)
    }

    private func rebuild() {
        let hiding = currentHidingState()
        refreshIcon(hidingEnabled: hiding)
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
            item.state = switch spec.state {
            case .none: .off
            case .on: .on
            case .off: .off
            }
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
        // A Task, not DispatchQueue.async: the body awaits the quarantine
        // repair, and an async closure is not a synchronous work item.
        //
        // `[weak self]` is not needed and would be wrong here — the toggle has
        // to finish and update the menu even if the controller went away, and
        // the closure only touches `self` after hopping to the main actor.
        Task.detached(priority: .userInitiated) {
            if elevate {
                // Bring the password dialog to the front: an LSUIElement app
                // has no Dock icon to click.
                await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
            }
            // Before anything is run, not after: a quarantined CLI blocks
            // inside dyld and never returns, so waiting to find out would mean
            // waiting forever.
            let repair = await repairQuarantineIfNeeded(cli: cli)
            let result = await Task.detached(priority: .userInitiated) { Self.run(plan) }.value
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if result.succeeded {
                    // A repair note is only interesting if the toggle worked;
                    // otherwise it is noise on a menu that reports state.
                    self?.message = repair
                } else if let repair {
                    self?.message = MenuBarModel.statusMessage("\(repair); \(result.output)")
                } else {
                    self?.message = MenuBarModel.statusMessage(result.output)
                }
                self?.rebuild()  // also refreshes the icon for the new state
            }
        }
    }

    /// Run commands in order, stopping at the first failure. Output is drained
    /// while the child runs: reading the pipe only after it exits deadlocks on
    /// a chatty child, and `hide` is not a quiet command.
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
            // Mirror the menu: a tick for a checked row, "informational" for a
            // greyed one, so the state is verifiable without a GUI.
            let tick = item.state == .on ? "\u{2713} " : ""
            let suffix = item.isEnabled ? "" : "  (informational)"
            print("\(tick)\(item.title)\(suffix)")
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
let controller = MenuController()
controller.attach(to: statusItem)

application.run()
