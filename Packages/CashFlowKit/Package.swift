// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CashFlowKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CashFlowKit", targets: ["CashFlowKit"]),
    ],
    targets: [
        .target(name: "CashFlowKit"),
        .testTarget(
            name: "CashFlowKitTests",
            dependencies: ["CashFlowKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
