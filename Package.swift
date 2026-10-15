// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LookAway",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LookAway", path: "Sources/LookAway")
    ]
)
