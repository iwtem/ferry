// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ferry",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FerryCore",
            targets: ["FerryCore"]
        ),
        .library(
            name: "FerryApp",
            targets: ["FerryApp"]
        ),
        .executable(
            name: "Ferry",
            targets: ["Ferry"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FerryCore",
            path: "Sources/FerryCore"
        ),
        .target(
            name: "FerryApp",
            dependencies: ["FerryCore"],
            path: "Sources/FerryApp"
        ),
        .executableTarget(
            name: "Ferry",
            dependencies: ["FerryApp"],
            path: "Sources/Ferry"
        ),
        .testTarget(
            name: "FerryCoreTests",
            dependencies: ["FerryCore"],
            path: "Tests/FerryCoreTests"
        )
    ]
)
