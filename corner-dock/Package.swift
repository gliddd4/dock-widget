// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CornerDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CornerDock",
            path: "Sources/CornerDock"
        )
    ]
)
