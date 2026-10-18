// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PANO",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PANO", path: "Sources/PANO")
    ]
)
