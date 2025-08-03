// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyBT",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SwiftyBT",
            targets: ["SwiftyBT"]),
        .executable(
            name: "SwiftyBTExample",
            targets: ["SwiftyBTExample"]),
        .executable(
            name: "clt-swiftybt",
            targets: ["CLTSwiftyBT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftyBT",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/swiftybt"),
        .executableTarget(
            name: "SwiftyBTExample",
            dependencies: ["SwiftyBT"],
            path: "Examples"),
        .executableTarget(
            name: "CLTSwiftyBT",
            dependencies: ["SwiftyBT"],
            path: "Sources/clt-swiftybt/Sources/CLTSwiftyBT"),
        .testTarget(
            name: "SwiftyBTTests",
            dependencies: ["SwiftyBT"],
            path: "Tests"),
    ]
) 