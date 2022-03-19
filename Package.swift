// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BlockChain_SDK_iOS",
    platforms: [.macOS(.v12), .iOS(.v13)],
    products: [.library(name: "BlockChain_SDK_iOS", targets: ["BlockChain_SDK_iOS"])],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "4.0.0"))
    ],
    targets: [
        .target(name: "BlockChain_SDK_iOS",
                dependencies: [
                    .product(name: "Starscream", package: "Starscream")
                ]),
        .testTarget(name: "BlockChain_SDK_iOSTests", dependencies: ["BlockChain_SDK_iOS"]),
    ]
)
