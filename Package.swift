// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SunsetHueCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SunsetHueCore",
            targets: ["SunsetHueCore"]
        ),
    ],
    targets: [
        .target(
            name: "SunsetHueCore",
            path: "Sources/SunsetHueCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SunsetHueCoreTests",
            dependencies: ["SunsetHueCore"],
            path: "Tests/SunsetHueCoreTests",
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
