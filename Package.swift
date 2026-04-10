// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MeetScribe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MeetScribe",
            targets: ["MeetScribe"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MeetScribe",
            resources: [
                .process("Resources/Assets")
            ]
        )
    ]
)
