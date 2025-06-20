// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vapor-apns",
    platforms: [
       .macOS(.v13),
       .iOS(.v16)
    ],
    products: [
        .library(name: "VaporAPNS", targets: ["VaporAPNS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "6.1.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.101.0"),
    ],
    targets: [
        .target(name: "VaporAPNS", dependencies: [
            .product(name: "APNS", package: "apnswift"),
            .product(name: "Vapor", package: "vapor"),
        ],
        swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]),
        .testTarget(name: "VaporAPNSTests", dependencies: [
            .target(name: "VaporAPNS"),
            .product(name: "XCTVapor", package: "vapor"),
        ],
        swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]),
    ]
)
