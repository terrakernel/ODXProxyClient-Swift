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
    targets: [
        .target(
            name: "ODXProxyClientSwift"
        ),
        .testTarget(
            name: "ODXProxyClientSwiftTests",
            dependencies: [
                "ODXProxyClientSwift"
            ],
            exclude: ["TestCredentials.swift.example"]
        )
    ]
)
