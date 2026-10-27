// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "inset-lint",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")
    ],
    targets: [
        .executableTarget(
            name: "inset-lint",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
