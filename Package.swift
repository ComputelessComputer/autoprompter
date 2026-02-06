// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Autoprompter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Autoprompter", targets: ["Autoprompter"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Autoprompter",
            dependencies: [],
            path: "Sources/Autoprompter"
        )
    ]
)
