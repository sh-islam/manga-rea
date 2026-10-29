// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kumo",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Kumo", targets: ["Kumo"]),
    ],
    targets: [
        .target(
            name: "Kumo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
