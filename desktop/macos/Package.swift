// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentStick",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "AgentStickApp", targets: ["AgentStickApp"]),
        .executable(name: "AgentStickCoreTests", targets: ["AgentStickCoreTests"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentStickApp",
            dependencies: [
                "AgentStickCore",
                "CZlib",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/AgentStickApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AgentStickApp/Info.plist",
                ])
            ]
        ),
        .target(
            name: "AgentStickCore",
            dependencies: []
        ),
        .executableTarget(
            name: "AgentStickHooks",
            dependencies: ["AgentStickCore"],
            path: "Sources/AgentStickHooks"
        ),
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "AgentStickCoreTests",
            dependencies: ["AgentStickCore"],
            path: "Tests/AgentStickAppTests"
        )
    ]
)
