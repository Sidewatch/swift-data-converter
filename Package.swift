// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DataConverter",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "DataConverter", targets: ["DataConverter"]),
    ],
    targets: [
        .target(name: "DataConverter", path: "Sources"),
        .testTarget(name: "DataConverterTests", dependencies: ["DataConverter"], path: "Tests"),
    ]
)
