// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Quicksave",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Quicksave", path: "Sources/Quicksave")
    ],
    swiftLanguageModes: [.v5]
)
