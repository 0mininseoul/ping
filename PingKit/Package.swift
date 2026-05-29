// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PingKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "PingKit", targets: ["PingKit"])
    ],
    targets: [
        .target(name: "PingKit"),
        .testTarget(name: "PingKitTests", dependencies: ["PingKit"])
    ]
)
