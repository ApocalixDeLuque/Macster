// swift-tools-version: 6.2

import PackageDescription

/// Approachable concurrency: `async` functions run on the caller's actor unless marked `@concurrent`.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI-facing modules run on the main actor by default.
let mainActorByDefault = approachableConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Macster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Macster", targets: ["Macster"]),
        .executable(name: "macster-watchdog", targets: ["MacsterWatchdog"]),
    ],
    targets: [
        // Decisions and text that can be tested without touching the system: parsing `pmset` and `sudo`
        // output, the setup script, timer and safety rules. Also the process runner.
        .target(name: "MacsterCore", swiftSettings: approachableConcurrency),

        // The menu bar app: state model, system integration, and the SwiftUI panel.
        .target(name: "MacsterApp", dependencies: ["MacsterCore"], swiftSettings: mainActorByDefault),
        .executableTarget(name: "Macster", dependencies: ["MacsterApp"], swiftSettings: mainActorByDefault),

        // Restores normal sleep if Macster exits while keeping the Mac awake. Darwin only, no Foundation.
        .executableTarget(name: "MacsterWatchdog", swiftSettings: approachableConcurrency),

        // Development tool: renders the panel and menu bar icons to PNG files for review.
        .executableTarget(
            name: "MacsterSnapshots",
            dependencies: ["MacsterApp", "MacsterCore"],
            path: "Tools/MacsterSnapshots",
            swiftSettings: mainActorByDefault
        ),

        .testTarget(name: "MacsterCoreTests", dependencies: ["MacsterCore"], swiftSettings: approachableConcurrency),
    ]
)
