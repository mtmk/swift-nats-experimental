// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "swift-nats-experimental",
    products: [
        .library(name: "NatsExperimental", targets: ["NatsExperimental"]),
    ],
    targets: [
        .target(name: "NatsExperimental"),
        .executableTarget(name: "example"),
        .testTarget(name: "NatsExperimentalTests", dependencies: ["NatsExperimental"]),
    ]
)
