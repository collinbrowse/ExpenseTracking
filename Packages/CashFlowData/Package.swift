// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CashFlowData",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CashFlowData", targets: ["CashFlowData"]),
    ],
    dependencies: [
        .package(path: "../CashFlowKit"),
    ],
    targets: [
        .target(
            name: "CashFlowData",
            dependencies: ["CashFlowKit"]
        ),
        .testTarget(
            name: "CashFlowDataTests",
            dependencies: ["CashFlowData", "CashFlowKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
