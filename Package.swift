// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JamfMapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "JamfMapper", targets: ["JamfMapper"]),
        .library(name: "JamfMapperCore", targets: ["JamfMapperCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "JamfMapper",
            dependencies: ["JamfMapperCore"]
        ),
        .target(
            name: "JamfMapperCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .testTarget(
            name: "JamfMapperCoreTests",
            dependencies: ["JamfMapperCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
