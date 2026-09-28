// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "headless-spotify",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "headless-spotify", targets: ["HeadlessSpotify"]),
        // Menu bar extra (NSStatusItem): the project name + Quit. Packaged as
        // an LSUIElement .app by scripts/build-menubar.sh.
        .executable(name: "headless-spotify-bar", targets: ["HeadlessSpotifyBar"]),
        // Accessory-policy injector dylib (DYLD_INSERT_LIBRARIES fallback).
        .library(name: "HeadlessSpotifyInjector", type: .dynamic, targets: ["CHeadlessInjector"]),
    ],
    targets: [
        .executableTarget(
            name: "HeadlessSpotify",
            path: "Sources/HeadlessSpotify"
        ),
        .target(
            name: "HeadlessSpotifyBarKit",
            path: "Sources/HeadlessSpotifyBarKit"
        ),
        .executableTarget(
            name: "HeadlessSpotifyBar",
            dependencies: ["HeadlessSpotifyBarKit"],
            path: "Sources/HeadlessSpotifyBar"
        ),
        .target(
            name: "CHeadlessInjector",
            path: "Sources/CHeadlessInjector",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .testTarget(
            name: "HeadlessSpotifyTests",
            dependencies: ["HeadlessSpotify", "HeadlessSpotifyBarKit"],
            path: "Tests/HeadlessSpotifyTests"
        ),
    ]
)
