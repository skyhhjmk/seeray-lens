// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SeeRayLens",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "SeeRayAnalytics", targets: ["SeeRayAnalytics"]),
    ],
    targets: [
        .target(
            name: "SeeRayAnalytics",
            path: "sdk/ios/Sources/SeeRayAnalytics"
        ),
        .testTarget(
            name: "SeeRayAnalyticsTests",
            dependencies: ["SeeRayAnalytics"],
            path: "sdk/ios/Tests/SeeRayAnalyticsTests"
        ),
    ]
)
