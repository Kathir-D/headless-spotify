// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "headless-spotify",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "headless-spotify", targets: ["HeadlessSpotify"]),
        // Accessory-policy injector dylib (DYLD_INSERT_LIBRARIES fallback).
        .library(name: "HeadlessSpotifyInjector", type: .dynamic, targets: ["CHeadlessInjector"]),
    ],
    targets: [
        .executableTarget(
            name: "HeadlessSpotify",
            path: "Sources/HeadlessSpotify"
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
            dependencies: ["HeadlessSpotify"],
            path: "Tests/HeadlessSpotifyTests"
        ),
    ]
)
