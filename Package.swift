// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabz",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NabzCore"),
        .executableTarget(name: "nabz", dependencies: ["NabzCore"]),
        .testTarget(name: "NabzCoreTests", dependencies: ["NabzCore"]),
    ]
)
