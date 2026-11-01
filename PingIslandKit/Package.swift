// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PingIslandKit",
    products: [
        .library(name: "PingIslandKit", targets: ["PingIslandKit"]),
    ],
    targets: [
        .target(name: "PingIslandKit"),
        .testTarget(name: "PingIslandKitTests", dependencies: ["PingIslandKit"]),
    ]
)
