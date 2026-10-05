// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ecore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "ECore",
            targets: ["ECore"]
        ),
        .library(
            name: "EMFBase",
            targets: ["EMFBase"]
        ),
        .library(
            name: "OCL",
            targets: ["OCL"]
        ),
        .library(
            name: "GenModel",
            targets: ["GenModel"]
        ),
        .library(
            name: "ECoreEdit",
            targets: ["ECoreEdit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
        .package(url: "https://github.com/swiftxml/SwiftXML.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "EMFBase",
            dependencies: [
                .product(name: "BigInt", package: "BigInt")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ECore",
            dependencies: [
                "EMFBase",
                "OCL",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "SwiftXML", package: "SwiftXML"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ECoreEdit",
            dependencies: [
                "ECore",
                "EMFBase",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "OCL",
            dependencies: ["EMFBase"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "GenModel",
            dependencies: [
                "ECore",
                .product(name: "SwiftXML", package: "SwiftXML"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GenModelTests",
            dependencies: [
                "GenModel",
                .product(name: "SwiftXML", package: "SwiftXML"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EMFBaseTests",
            dependencies: ["EMFBase"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ECoreTests",
            dependencies: ["ECore"],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ECoreEditTests",
            dependencies: ["ECoreEdit", "ECore", "EMFBase"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OCLTests",
            dependencies: ["OCL"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
