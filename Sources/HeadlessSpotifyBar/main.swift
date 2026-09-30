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

// MARK: - The Automation permission

/// Read whether macOS lets this app control Spotify, without blocking the menu.
///
/// Implemented as one `osascript` run rather than
/// `AEDeterminePermissionToAutomateTarget`. That was the first attempt and it
/// is wrong: measured on this machine, the AE call does not return within eight
/// seconds when made from a process without a full app bundle, so calling it
/// from `menuWillOpen` would hang the menu on a thread that cannot be
/// interrupted. The Apple Event route also has nothing to gain: the CLI already
/// drives Spotify through `osascript`, so asking through the same mechanism is
/// the only answer that cannot disagree with the command that then fails.
///
/// The first run of this *is* the request — sending a real Apple Event is what
/// makes macOS prompt, and there is no API to ask without sending one. It is
/// run off the main thread with a timeout, and its result is published back on
/// the main actor.
private func probeAutomation(
    completion: @escaping @MainActor (AutomationState) -> Void
) {
    DispatchQueue.global(qos: .utility).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Automation.osascript)
        process.arguments = ["-e", Automation.probeScript]
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            Task { @MainActor in completion(.unknown) }
            return
        }
        // Drain stderr on its own queue. `readDataToEndOfFile` blocks until the
        // pipe closes, so reading it on this thread would defeat the timeout
        // entirely — and polling `availableData` instead is a guess about
        // whether the writer has flushed yet, which is not a question worth
        // asking about an error message that decides the UI.
        //
        // A box rather than a captured `var`: Swift 6 will not let two
        // concurrent closures touch one, and the alternative — a lock — is
        // strictly more machinery for one string written once and read once.
        final class Box: @unchecked Sendable { var text = "" }
        let captured = Box()
        let collector = DispatchQueue(label: "headless-spotify.probe")
        collector.async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            captured.text = String(data: data, encoding: .utf8) ?? ""
        }
        // A timeout, because the very first call is what raises the system
        // dialog, and that call blocks until the dialog is answered. With no one
        // at the keyboard that is unbounded, and this process must stay
        // killable.
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            Task { @MainActor in completion(.unknown) }
            return
        }
        // The writer has closed, so the reader finishes on its own; wait for it
        // rather than racing it.
        collector.sync {}
        let state = Automation.state(exitCode: process.terminationStatus, standardError: captured.text)
        Task { @MainActor in completion(state) }
    }
}

/// Ask macOS for permission to control Spotify.
///
/// The status item is an `LSUIElement` app: no Dock icon, no window, so there
/// is nothing the user could click to bring the system dialog forward. The
/// caller activates the app first; that is the whole reason this is more than
/// "run the script".
private func requestAutomationGrant() {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Automation.osascript)
        process.arguments = ["-e", Automation.probeScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - Menu controller

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let menu = NSMenu()
    private var cli: String?
    private var isBusy = false
    private var message: String?
    private var automation: AutomationState = .unknown
    private weak var button: NSStatusBarButton?
    /// Set while a probe is in flight, so opening the menu twice does not leave
    /// two `osascript` processes competing over the same prompt.
    private var isProbing = false

    func attach(to statusItem: NSStatusItem) {
        menu.delegate = self
        button = statusItem.button
        rebuild()
        statusItem.menu = menu
        // Once, shortly after launch. macOS only prompts once per
        // (client, target) pair, so this is the one chance to ask — and asking
        // at launch is the only time it happens without the user having already
        // hit a failure and gone looking for the cause.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshAutomation()
        }
    }

    /// Re-read the permission, off the main thread.
    ///
    /// Skipped once granted. Re-probing a granted app would send an Apple Event
    /// on every menu open for a state that cannot change without the user
    /// visiting System Settings. `.needsGrant` and `.refused` *are* re-read,
    /// because the user answers the dialog and comes straight back to this menu
    /// and the row has to be gone by then.
    private func refreshAutomation(force: Bool = false) {
        guard !isProbing else { return }
        if !force, automation == .granted { return }
        isProbing = true
        probeAutomation { [weak self] state in
            guard let self else { return }
            self.isProbing = false
            self.automation = state
            self.rebuild()
        }
    }

    /// Recompute state every time the menu opens, so the label and the icon
    /// always reflect reality (including changes made from the terminal or
    /// the watcher).
    func menuWillOpen(_ menu: NSMenu) {
        cli = cliPath()
        message = nil
        refreshAutomation()
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
            message: message,
            automation: automation
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
            case .requestAutomation:
                item.action = #selector(grantAutomation(_:))
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

    /// Ask macOS for permission to control Spotify.
    ///
    /// The status item is an `LSUIElement` app: it has no Dock icon and no
    /// window, so there is nothing the user could click to bring the system
    /// dialog to the front. Activating first is the whole reason this is more
    /// than "run the script".
    @objc private func grantAutomation(_ sender: Any?) {
        message = Automation.permissionMessage
        rebuild()
        NSApp.activate(ignoringOtherApps: true)
        requestAutomationGrant()
        // Re-read after the dialog closes, so the row disappears on its own
        // rather than waiting for the user to open the menu again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshAutomation(force: true)
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
                } else if let blocked = Automation.failureState(output: result.output) {
                    // The command failed on the Apple Events permission. The
                    // probe can miss this — the grant is checked against the
                    // responsible process and inherits down the chain — so the
                    // command's own output is the evidence, and it is turned
                    // into a row the user can act on rather than a raw -1743.
                    self?.automation = blocked
                    self?.message = MenuBarModel.statusMessage(
                        blocked == .refused ? Automation.blockedMessage : Automation.permissionMessage
                    )
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
