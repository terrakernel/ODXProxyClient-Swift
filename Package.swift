// swift-tools-version: 6.2.0

import PackageDescription

let package = Package(
    name: "ODXProxyClientSwift",
    platforms: [
        .macOS(.v12), 
        .iOS(.v15), 
        .tvOS(.v15), 
        .watchOS(.v8),
        .visionOS(.v1),
        .macCatalyst(.v15)
    ],
    products: [
        .library(
            name: "ODXProxyClientSwift",
            targets: ["ODXProxyClientSwift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "ODXProxyClientSwift"
        ),
        .testTarget(
            name: "ODXProxyClientSwiftTests",
            dependencies: [
                "ODXProxyClientSwift",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)