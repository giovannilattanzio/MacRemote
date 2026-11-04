// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacRemote",
    platforms: [.macOS(.v12)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "MacRemoteKit"),
        .executableTarget(
            name: "MacRemote",
            dependencies: ["MacRemoteKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MacRemoteKitTests", dependencies: ["MacRemoteKit"]),
    ]
)
