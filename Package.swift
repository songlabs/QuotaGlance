// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaGlanceCore",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "QuotaGlanceCore", targets: ["QuotaGlanceCore"]),
    ],
    targets: [
        .target(name: "QuotaGlanceCore"),
        .testTarget(
            name: "QuotaGlanceCoreTests",
            dependencies: ["QuotaGlanceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
