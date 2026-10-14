// swift-tools-version: 6.0
// Mac-hosted test runner for the logic layer, so tests run with `swift test` and no Simulator.
// The app itself is built from project.yml (XcodeGen). Screens, speech and location are not in here.
import PackageDescription

let package = Package(
    name: "Baxi",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "Baxi",
            path: "Baxi",
            exclude: ["App", "Screens", "Info.plist", "Resources/Assets.xcassets", "Resources/Content", "Resources/PrivacyInfo.xcprivacy",
                      ],
            sources: ["Core", "Models", "Services"],
            resources: [.process("Resources/Data"), .process("Resources/Routes")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "baxi-transcript",
            dependencies: ["Baxi"],
            path: "Tools/transcript",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BaxiTests",
            dependencies: ["Baxi"],
            path: "BaxiTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
