// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SunsetHueCore",
    platforms: [
        .macOS(.v14),
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
            path: "Sources/SunsetHueCore"
        ),
        .testTarget(
            name: "SunsetHueCoreTests",
            dependencies: ["SunsetHueCore"],
            path: "Tests/SunsetHueCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
