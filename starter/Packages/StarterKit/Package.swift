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

// The shared half: the data, the model, the commands, and views that make
// sense on any platform. It declares iOS as well as macOS, and `make check`
// compiles it for iOS, so a Mac-only API here is a build error today rather
// than a pile of `#if os(macOS)` the day an iOS app arrives. Mac-only code
// lives in StarterMacKit, whose manifest says macOS and nothing else.
let package = Package(
    name: "StarterKit", platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "Core", targets: ["Core"]), .library(name: "UI", targets: ["UI"])],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
        .package(url: "https://github.com/pointfreeco/swift-issue-reporting", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "swift-issue-reporting"),
            ], swiftSettings: shared),
        .target(
            name: "UI",
            dependencies: [
                "Core", .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "swift-issue-reporting"),
                .product(name: "Sharing", package: "swift-sharing"),
            ], swiftSettings: shared),
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
