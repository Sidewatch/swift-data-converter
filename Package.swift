// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DataConverter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DataConverter", targets: ["DataConverter"]),
    ],
    targets: [
        .target(name: "DataConverter", path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "DataConverterTests", dependencies: ["DataConverter"], path: "Tests"),
    ]
)
