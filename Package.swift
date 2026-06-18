// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VokabKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VokabKit", targets: ["VokabKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "VokabKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VokabKitTests",
            dependencies: ["VokabKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VokabKitIntegrationTests",
            dependencies: ["VokabKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
