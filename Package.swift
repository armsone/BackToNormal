// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BackToNormal",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "BackToNormalCore",
            path: "Sources/BackToNormalCore"
        ),
        .executableTarget(
            name: "BackToNormal",
            dependencies: ["BackToNormalCore"],
            path: "Sources/BackToNormal"
        ),
        .testTarget(
            name: "BackToNormalCoreTests",
            dependencies: ["BackToNormalCore"],
            path: "Tests/BackToNormalCoreTests"
        ),
        .testTarget(
            name: "BackToNormalTests",
            dependencies: ["BackToNormal"],
            path: "Tests/BackToNormalTests"
        ),
    ]
)
