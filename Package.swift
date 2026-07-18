// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CursorUsageTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CursorUsageTray",
            path: "Sources/CursorUsageTray"
        )
    ]
)
