// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabz",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "NabzCore"),
        // Phase-1 terminal presentation. Depends on the UI-agnostic core, never the
        // reverse (PRD §4/§6). Phases 2–3 add their own presentation on the same core.
        .target(name: "NabzTUI", dependencies: ["NabzCore"]),
        .executableTarget(name: "nabz", dependencies: [
            "NabzCore", "NabzTUI",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "NabzCoreTests", dependencies: ["NabzCore"]),
        .testTarget(name: "NabzTUITests", dependencies: ["NabzTUI"]),
    ]
)
