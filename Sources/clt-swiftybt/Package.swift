// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CLTSwiftyBT",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "clt-swiftybt",
            targets: ["CLTSwiftyBT"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "CLTSwiftyBT",
            dependencies: ["SwiftyBT"]),
    ]
) 