// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileLens",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FileLens",
            path: "Sources/FileLens",
            resources: [
                .copy("Resources/classification_rules.json"),
                .copy("Resources/identification_rules.json")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
