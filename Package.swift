// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HealthyPops",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "HealthyPops", path: "Sources/HealthyPops")
    ]
)
