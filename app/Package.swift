// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Quicksave",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Quicksave", path: "Sources/Quicksave")
    ]
)
