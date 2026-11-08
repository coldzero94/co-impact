// swift-tools-version: 6.2
import PackageDescription

// Mirrors the app target's concurrency settings (Xcode's "Approachable Concurrency").
// No default MainActor isolation here: engine code must stay usable off the main actor.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "ImpactKit",
    // macOS lets `swift test` run the engine tests without an iOS simulator.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ImpactEngine", targets: ["ImpactEngine"]),
    ],
    targets: [
        .target(name: "ImpactEngine", swiftSettings: swiftSettings),
        .testTarget(name: "ImpactEngineTests", dependencies: ["ImpactEngine"], swiftSettings: swiftSettings),
    ]
)
