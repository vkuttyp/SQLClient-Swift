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
                .enableExperimentalFeature("StrictConcurrency=complete"),
                // Pass both Homebrew prefix locations to the C compiler so
                // angle bracket includes in CFreeTDS.h resolve on both
                // Intel (/usr/local) and Apple Silicon (/opt/homebrew) Macs.
                // The compiler silently ignores paths that don't exist,
                // so providing both is safe.
                .unsafeFlags([
                    "-Xcc", "-I/opt/homebrew/opt/freetds/include",  // Apple Silicon
                    "-Xcc", "-I/usr/local/opt/freetds/include",     // Intel
                ], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/freetds/lib",  // Apple Silicon
                    "-L/usr/local/opt/freetds/lib",     // Intel
                ], .when(platforms: [.macOS])),
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
