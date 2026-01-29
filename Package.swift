// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Whisker",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Whisker",
            targets: ["Whisker"]
        ),
        .executable(
            name: "Examples",
            targets: ["Examples"]
        ),
    ],
    targets: [
        .target(
            name: "Whisker",
            path: "Sources/Whisker"
        ),
        .executableTarget(
            name: "Examples",
            dependencies: ["Whisker"],
            path: "Sources/Examples"
        ),
        .testTarget(
            name: "WhiskerTests",
            dependencies: ["Whisker"],
            path: "Tests/WhiskerTests"
        ),
    ]
)
