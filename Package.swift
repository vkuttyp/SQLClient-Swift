// swift-tools-version: 5.9
import PackageDescription
import Foundation

// SPI Runners do not have FreeTDS installed. 
// We detect its presence to avoid Clang scanner errors on SPI.
let hasFreeTDS: Bool = {
    // Manual override for local testing
    if ProcessInfo.processInfo.environment["SKIP_FREETDS"] != nil { return false }
    
    let standardPaths = [
        "/opt/homebrew/include/sybdb.h",      // macOS Apple Silicon
        "/usr/local/include/sybdb.h",         // macOS Intel
        "/usr/include/sybdb.h",               // Linux (Standard)
        "/usr/include/freetds/sybdb.h",       // Linux (Alternative)
        "/opt/homebrew/opt/freetds/include/sybdb.h" // Brew opt path
    ]
    return standardPaths.contains { FileManager.default.fileExists(atPath: $0) }
}()

var packageTargets: [Target] = [
    .target(
        name: "SQLClientSwift",
        dependencies: hasFreeTDS ? ["CFreeTDS"] : [],
        path: "Sources/SQLClientSwift",
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency=complete"),
        ] + (hasFreeTDS ? [.define("FREETDS_FOUND")] : []),
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

if hasFreeTDS {
    packageTargets.append(
        .systemLibrary(
            name: "CFreeTDS",
            path: "Sources/CFreeTDS",
            pkgConfig: "freetds",
            providers: [
                .brew(["freetds"]),
                .apt(["freetds-dev"]),
            ]
        )
    )
}

let package = Package(
    name: "SQLClientSwift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SQLClientSwift",
            targets: ["SQLClientSwift"]
        ),
    ],
    targets: packageTargets
)
