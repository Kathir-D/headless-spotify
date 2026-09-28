// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "headless-spotify",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "headless-spotify", targets: ["HeadlessSpotify"])
    ],
    targets: [
        .executableTarget(
            name: "HeadlessSpotify",
            path: "Sources/HeadlessSpotify"
        ),
        .testTarget(
            name: "HeadlessSpotifyTests",
            dependencies: ["HeadlessSpotify"],
            path: "Tests/HeadlessSpotifyTests"
        ),
    ]
)
