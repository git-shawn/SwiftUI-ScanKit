// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScanKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
        .macCatalyst(.v14)
    ],
    products: [
        .library(
            name: "ScanKit",
            targets: ["ScanKit"]),
    ],
    dependencies: [
        // No Dependencies
    ],
    targets: [
        .target(
            name: "ScanKit",
            dependencies: []),
        .testTarget(
            name: "ScanKitTests",
            dependencies: ["ScanKit"]),
    ]
)
