// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "stenograf",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "StenografCore",
            path: "Sources/StenografCore"
        ),
        .executableTarget(
            name: "stenograf",
            dependencies: ["StenografCore"],
            path: "Sources/stenograf"
        ),
        .executableTarget(
            name: "StenografApp",
            dependencies: ["StenografCore"],
            path: "Sources/StenografApp"
        ),
        .testTarget(
            name: "StenografCoreTests",
            dependencies: ["StenografCore"],
            path: "Tests/StenografCoreTests"
        ),
    ]
)
