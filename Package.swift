// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ChickenNeck",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ChickenNeck",
            path: "Sources/ChickenNeck"
        )
    ],
    swiftLanguageModes: [.v5]
)
