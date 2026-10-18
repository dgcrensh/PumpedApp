// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PumpedCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PumpedCore", targets: ["PumpedCore"]),
    ],
    targets: [
        .target(name: "PumpedCore"),
        .testTarget(name: "PumpedCoreTests", dependencies: ["PumpedCore"]),
    ]
)
