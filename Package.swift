// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyBT",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftyBT",
            targets: ["SwiftyBT"]
        ),
    ],
    dependencies: [
        // Здесь можно добавить зависимости в будущем
    ],
    targets: [
        .executableTarget(
            name: "SwiftyBT",
            dependencies: [],
            path: "Sources/SwiftyBT"
        ),
    ]
)
