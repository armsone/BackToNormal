// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BTN",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "BTNCore",
            path: "Sources/BTNCore"
        ),
        .executableTarget(
            name: "BTN",
            dependencies: ["BTNCore"],
            path: "Sources/BTN"
        ),
        .testTarget(
            name: "BTNCoreTests",
            dependencies: ["BTNCore"],
            path: "Tests/BTNCoreTests"
        ),
        .testTarget(
            name: "BTNTests",
            dependencies: ["BTN"],
            path: "Tests/BTNTests"
        ),
    ]
)
