// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickSnap",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuickSnap", targets: ["QuickSnap"])],
    targets: [
        .target(name: "QuickSnapCore"),
        .executableTarget(name: "QuickSnap", dependencies: ["QuickSnapCore"]),
        .testTarget(name: "QuickSnapCoreTests", dependencies: ["QuickSnapCore"])
    ]
)
