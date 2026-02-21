// swift-tools-version: 5.9
// Package.swift for vkuttyp/SQLClient-Swift

import PackageDescription

let package = Package(
    name: "SQLClientSwift",

    // Explicit platform minimums — required for async/await and modern Swift Concurrency.
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
    ],

    products: [
        .library(
            name: "SQLClientSwift",
            targets: ["SQLClientSwift"]
        ),
    ],

    targets: [
        // ── System library target for FreeTDS ─────────────────────────────
        // Enables `import CFreeTDS` in Swift without a bridging header,
        // which is required for Linux / Swift Package Manager builds.
        // On macOS/iOS you still need to link libsybdb.a manually.
        .systemLibrary(
            name: "CFreeTDS",
            pkgConfig: "freetds",           // resolved via `pkg-config freetds`
            providers: [
                .brew(["freetds"]),          // macOS: brew install freetds
                .apt(["freetds-dev"]),       // Linux: apt install freetds-dev
            ]
        ),

        // ── Main library target ───────────────────────────────────────────
        .target(
            name: "SQLClientSwift",
            dependencies: ["CFreeTDS"],
            path: "Sources/SQLClientSwift",
            swiftSettings: [
                // Enable strict concurrency checking (Swift 5.9+)
                .enableExperimentalFeature("StrictConcurrency=complete"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/freetds/lib"], .when(platforms: [.macOS])),
                .linkedLibrary("sybdb"),
                .linkedLibrary("iconv", .when(platforms: [.macOS]))
            ]
        ),

        // ── Unit & integration test target ───────────────────────────────
        // Integration tests require a live SQL Server; controlled via
        // environment variables HOST, DATABASE, USERNAME, PASSWORD.
        .testTarget(
            name: "SQLClientSwiftTests",
            dependencies: ["SQLClientSwift"],
            path: "Tests/SQLClientSwiftTests"
        ),
    ]
)
