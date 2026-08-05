// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DouhuaPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DouhuaPet", targets: ["DouhuaPet"]),
        .executable(name: "DouhuaPixelDemo", targets: ["DouhuaPixelDemo"]),
    ],
    targets: [
        .executableTarget(
            name: "DouhuaPet",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "DouhuaPixelDemo",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DouhuaPetTests",
            dependencies: ["DouhuaPet"]
        ),
    ]
)
