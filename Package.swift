// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FanKitCore", targets: ["FanKitCore"]),
        .executable(name: "fankitctl", targets: ["fankitctl"]),
        .executable(name: "FanKitHelper", targets: ["FanKitHelper"]),
        .executable(name: "FanKit", targets: ["FanKitApp"]),
    ],
    targets: [
        .target(
            name: "CHIDTemperature",
            publicHeadersPath: "include"
        ),
        .target(
            name: "FanKitCore",
            dependencies: ["CHIDTemperature"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FanKitHelper",
            dependencies: ["FanKitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FanKitApp",
            dependencies: ["FanKitCore"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-parse-as-library"])]
        ),
        .executableTarget(
            name: "fankitctl",
            dependencies: ["FanKitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FanKitCoreTests",
            dependencies: ["FanKitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
