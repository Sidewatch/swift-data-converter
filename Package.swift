// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DataConverter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DataConverter", targets: ["DataConverter"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
    ],
    targets: [
        .target(name: "DataConverter", dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions")], path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "DataConverterTests", dependencies: ["DataConverter"], path: "Tests"),
    ]
)
