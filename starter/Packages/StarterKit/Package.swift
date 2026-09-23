// swift-tools-version: 6.2

import PackageDescription

// Every target gets the same two settings, spelled out rather than left to a
// default that moves between toolchains:
//
//   * Swift 6 language mode — strict concurrency checking, no opt-out.
//   * Default actor isolation `nil`, i.e. nonisolated, in UI targets too.
//     `@MainActor` is marked where it is needed. Making it the default hides
//     which code actually has to be on the main actor.
let shared: [SwiftSetting] = [.swiftLanguageMode(.v6), .defaultIsolation(nil)]

let package = Package(
    name: "StarterKit", platforms: [.macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]), .library(name: "UI", targets: ["UI"]),
        .executable(name: "StarterMac", targets: ["StarterMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.13.1"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ], swiftSettings: shared),
        .target(
            name: "UI",
            dependencies: [
                "Core", .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "Sharing", package: "swift-sharing"),
            ], swiftSettings: shared),
        // The Mac app. Pure SwiftPM — `build.sh` wraps this executable in a
        // bundle; there is no Xcode project for it and there is not meant to
        // be one.
        .executableTarget(name: "StarterMac", dependencies: ["Core", "UI"], swiftSettings: shared),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core", .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ], swiftSettings: shared),
        .testTarget(
            name: "UITests",
            dependencies: [
                "UI", .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ], swiftSettings: shared),
    ])
