// swift-tools-version: 5.9
import PackageDescription
import Foundation

// SPI Runners do not have FreeTDS installed. 
// We detect its presence to avoid Clang scanner errors on SPI.
let hasFreeTDS: Bool = {
    // Manual override for local testing
    if ProcessInfo.processInfo.environment["SKIP_FREETDS"] != nil { return false }
    
    // 1. Check if the header exists in standard paths.
    let standardPaths = [
        "/opt/homebrew/include/sybdb.h",      // macOS Apple Silicon
        "/usr/local/include/sybdb.h",         // macOS Intel
        "/usr/include/sybdb.h",               // Linux (Standard)
        "/usr/include/freetds/sybdb.h",       // Linux (Alternative)
        "/opt/homebrew/opt/freetds/include/sybdb.h" // Brew opt path
    ]
    let headerExists = standardPaths.contains { FileManager.default.fileExists(atPath: $0) }
    guard headerExists else { return false }

    // 2. Check if pkg-config can actually find it. 
    // If headers exist but pkg-config fails, the systemLibrary target will cause a build failure.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config", "--exists", "freetds"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
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
