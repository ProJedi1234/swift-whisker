// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Whisker",
    platforms: [
        .macOS(.v13)
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
        .executable(
            name: "WhiskerLifecycleFixture",
            targets: ["WhiskerLifecycleFixture"]
        )
    ],
    targets: [
        .target(
            name: "Whisker",
            dependencies: ["CWhiskerSignals"],
            path: "Sources/Whisker"
        ),
        .target(
            name: "CWhiskerSignals",
            path: "Sources/CWhiskerSignals",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Examples",
            dependencies: ["Whisker"],
            path: "Sources/Examples"
        ),
        .executableTarget(
            name: "WhiskerLifecycleFixture",
            dependencies: ["Whisker"],
            path: "Tests/WhiskerLifecycleFixture"
        ),
        .target(
            name: "CWhiskerTestSupport",
            path: "Tests/CWhiskerTestSupport",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("util", .when(platforms: [.linux]))]
        ),
        .testTarget(
            name: "WhiskerTests",
            dependencies: ["Whisker", "CWhiskerTestSupport"],
            path: "Tests/WhiskerTests"
        )
    ]
)
