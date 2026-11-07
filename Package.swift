// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "myss",
    platforms: [.macOS(.v26)],
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
                .linkedFramework("FoundationModels")
            ]
        ),
        .testTarget(name: "myssTests", dependencies: ["myss"])
    ]
)
