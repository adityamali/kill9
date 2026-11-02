// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kill9Core",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Kill9Core", targets: ["Kill9Core"])],
    targets: [
        .target(name: "Kill9Core", path: "Kill9/Core"),
        .testTarget(name: "Kill9CoreTests", dependencies: ["Kill9Core"])
    ]
)
