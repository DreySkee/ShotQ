// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShotQueue",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShotQueue",
            path: "Sources/ShotQueue"
        )
    ]
)
