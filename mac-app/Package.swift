// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Callmet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Callmet", targets: ["Callmet"])
    ],
    targets: [
        .executableTarget(
            name: "Callmet",
            path: "Sources"
        )
    ]
)
