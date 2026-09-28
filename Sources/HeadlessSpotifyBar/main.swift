// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// Entry point for the menu bar extra. Thin by design: NSStatusItem + a menu
// built from MenuBarModel, then run the AppKit event loop.
//
// This binary is packaged as an LSUIElement .app (see
// scripts/build-menubar.sh) so it has no Dock icon and no Cmd-Tab entry —
// the same trick this project applies to Spotify. It needs no special
// permission: menu bar extras are always allowed.

import AppKit
import Foundation

import HeadlessSpotifyBarKit

// Version comes from the app bundle's Info.plist (written at build time from
// the VERSION file). Unbundled runs (--print-menu-spec) report "dev".
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

// `--print-menu-spec` mirrors `watch --print-agent-plist`: a hermetic,
// GUI-free way to inspect the menu, used by scripts/smoke-test.sh.
if CommandLine.arguments.contains("--print-menu-spec") {
    for item in MenuBarModel.menuItems(version: version) {
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

let menu = NSMenu()
for spec in MenuBarModel.menuItems(version: version) {
    if spec.isSeparator {
        menu.addItem(.separator())
        continue
    }
    let item = NSMenuItem(
        title: spec.title,
        action: spec.isQuit ? #selector(NSApplication.terminate(_:)) : nil,
        keyEquivalent: spec.isQuit ? "q" : ""
    )
    if spec.isQuit {
        item.target = application
    }
    item.isEnabled = spec.isEnabled
    menu.addItem(item)
}
statusItem.menu = menu

application.run()
