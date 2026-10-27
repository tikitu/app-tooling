// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ScrollCheck", platforms: [.macOS(.v14)],
  products: [.library(name: "ScrollCheck", type: .dynamic, targets: ["ScrollCheckLoader"])],
  targets: [
    .target(name: "ScrollCheck"),
    .target(name: "ScrollCheckLoader", dependencies: ["ScrollCheck"]),
  ])
