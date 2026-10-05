// swift-tools-version: 6.2

import PackageDescription

// The same settings as StarterKit, for the same reason: default isolation is
// spelled out as nonisolated, and code opts in to `@MainActor`.
let shared: [SwiftSetting] = [.swiftLanguageMode(.v6), .defaultIsolation(nil)]

// The Mac half. Declaring macOS as the *only* platform is the whole design: a
// Mac-only API is at home here, needs no `#if os(macOS)` guard, and cannot
// leak into StarterKit, which cannot see this package. An iOS app would get a
// package of its own, beside this one, in the same way.
let package = Package(
    name: "StarterMacKit", platforms: [.macOS(.v26)],
    products: [.executable(name: "StarterMac", targets: ["StarterMac"])],
    dependencies: [
        .package(path: "../StarterKit"),
        // Named again here, although StarterKit already depends on them,
        // because a target can only use a product of a package its own
        // manifest lists.
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
        .package(url: "https://github.com/pointfreeco/swift-issue-reporting", from: "2.1.0"),
    ],
    targets: [
        // The Mac's views: the window, the list and its keyboard handling,
        // the menu bar.
        .target(
            name: "MacUI",
            dependencies: [
                .product(name: "Core", package: "StarterKit"),
                .product(name: "UI", package: "StarterKit"),
                .product(name: "Sharing", package: "swift-sharing"),
            ], swiftSettings: shared),
        // The Mac app. Pure SwiftPM — `build.sh` wraps this executable in a
        // bundle; there is no Xcode project for it and there is not meant to
        // be one.
        .executableTarget(
            name: "StarterMac",
            dependencies: [
                "MacUI", .product(name: "Core", package: "StarterKit"),
                .product(name: "UI", package: "StarterKit"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "swift-issue-reporting"),
            ], swiftSettings: shared),
    ])
