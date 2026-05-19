// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PerchApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PerchApp", targets: ["PerchApp"])
    ],
    targets: [
        .target(
            name: "PerchAppCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PerchApp",
            dependencies: ["PerchAppCore"]
        ),
        .testTarget(
            name: "PerchAppCoreTests",
            dependencies: ["PerchAppCore"]
        ),
    ]
)
