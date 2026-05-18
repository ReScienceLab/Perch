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
        .executableTarget(
            name: "PerchApp",
            resources: [.process("Resources")]
        ),
    ]
)
