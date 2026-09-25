// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GymPass",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "GymPassShared", targets: ["GymPassShared"]),
        .library(name: "GymPassCore", targets: ["GymPassCore"]),
        .library(name: "GymPassAgentCore", targets: ["GymPassAgentCore"]),
        .executable(name: "GymPassAgent", targets: ["GymPassAgent"]),
        .executable(name: "GymPassApp", targets: ["GymPassApp"]),
        .executable(name: "GymPassTests", targets: ["GymPassTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.27.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.12.0"),
    ],
    targets: [
        .target(
            name: "GymPassShared",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GymPassCore",
            dependencies: [
                "GymPassShared",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GymPassAgentCore",
            dependencies: ["GymPassCore", "GymPassShared"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GymPassAgent",
            dependencies: ["GymPassAgentCore", "GymPassCore", "GymPassShared"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GymPassApp",
            dependencies: ["GymPassCore", "GymPassShared"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // A self-contained test runner. swift-testing discovery is broken when
        // only CommandLineTools is installed, so GymPass ships a tiny harness
        // that runs the same tests reliably with `swift run GymPassTests`.
        .executableTarget(
            name: "GymPassTests",
            dependencies: ["GymPassCore", "GymPassAgentCore", "GymPassShared"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
