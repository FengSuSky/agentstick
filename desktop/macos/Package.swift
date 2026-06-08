// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentStick",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "AgentStickApp", targets: ["AgentStickApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentStickApp",
            dependencies: [
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
            name: "CZlib",
            path: "Sources/CZlib",
            publicHeadersPath: "."
        )
    ]
)
