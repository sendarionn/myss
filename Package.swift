// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "myss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "myss", targets: ["myss"])
    ],
    targets: [
        .executableTarget(
            name: "myss",
            path: "Sources/myss",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(name: "myssTests", dependencies: ["myss"])
    ]
)
