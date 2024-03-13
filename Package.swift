// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "swift-nats-experimental",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NatsExperimental", targets: ["NatsExperimental"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
    ],
    targets: [
        .target(name: "NatsExperimental", dependencies: [
            .product(name: "NIO", package: "swift-nio"),
        ]),
        .executableTarget(name: "example", dependencies: ["NatsExperimental"]),
        .testTarget(name: "NatsExperimentalTests", dependencies: ["NatsExperimental"]),
    ]
)
