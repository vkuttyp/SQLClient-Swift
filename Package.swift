// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SQLClientSwift",
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
        // systemLibrary uses pkg-config to find FreeTDS at build time.
        // No hardcoded paths, no unsafeFlags — works as an SPM dependency.
        //   macOS : brew install freetds && brew install pkg-config
        //   Linux : sudo apt install freetds-dev
        .systemLibrary(
            name: "CFreeTDS",
            path: "Sources/CFreeTDS",
            pkgConfig: "freetds",
            providers: [
                .brew(["freetds"]),
                .apt(["freetds-dev"]),
            ]
        ),
        .target(
            name: "SQLClientSwift",
            dependencies: ["CFreeTDS"],
            path: "Sources/SQLClientSwift",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
            ],
            linkerSettings: [
                .linkedLibrary("sybdb", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "SQLClientSwiftTests",
            dependencies: ["SQLClientSwift"],
            path: "Tests/SQLClientSwiftTests"
        ),
    ]
)