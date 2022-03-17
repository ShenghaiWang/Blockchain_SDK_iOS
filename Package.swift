// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Blockchain_SDK_iOS",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "Blockchain_SDK_iOS", targets: ["Blockchain_SDK_iOS"])],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "4.0.0"))
    ],
    targets: [
        .target(name: "Blockchain_SDK_iOS",
                dependencies: [
                    .product(name: "Starscream", package: "Starscream")
                ]),
        .testTarget(name: "Blockchain_SDK_iOSTests", dependencies: ["Blockchain_SDK_iOS"]),
    ]
)
