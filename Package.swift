// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SynesthesiaCollector",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SynesthesiaData"),
        .executableTarget(
            name: "SynesthesiaCollector",
            dependencies: ["SynesthesiaData"]
        ),
        .executableTarget(
            name: "ColorShow",
            dependencies: ["SynesthesiaData"]
        )
    ],
    swiftLanguageModes: [.v5]
)
