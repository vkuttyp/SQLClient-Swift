# SQLClient-Swift

A modern, high-performance Swift client for **Microsoft SQL Server**, built for macOS, iOS, and Linux.

This library is a lightweight Swift wrapper around the **FreeTDS (db-lib)** C library. It provides a clean, native Swift interface with full support for modern Swift features like `Async/Await`.

## Features

- **Modern Concurrency**: Full `Async/Await` support for non-blocking database operations.
- **Cross-Platform**: Works seamlessly on macOS (via Homebrew) and Linux (via APT).
- **FreeTDS 1.x Optimized**: 
    - Supports modern SQL Server types: `DATETIME2`, `NVARCHAR(MAX)`, `UNIQUEIDENTIFIER` (UUID), etc.
    - Handles affected-row counts (`dbcount`) for DML operations.
    - Support for named encryption modes (`off`, `request`, `require`, `strict` for TDS 8.0).
- **Robust & Compatible**:
    - Automatically detects and handles different FreeTDS build modes (Sybase vs. Microsoft).
    - Gracefully falls back on advanced features for older FreeTDS versions.
    - Fixes the legacy "MONEY truncation" bug in older libraries.
- **Thread-Safe**: Uses internal serial dispatch queues to safely manage the underlying C state.

## Installation

### 1. Install FreeTDS

#### macOS (Homebrew)
```bash
brew install freetds
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install freetds-dev freetds-bin
```

### 2. Add to Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vkuttyp/SQLClient-Swift.git", from: "1.0.0")
]
```

And add it to your target:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SQLClient", package: "SQLClient-Swift")
        ]
    )
]
```

## Usage

### Simple Connection (Async/Await)

```swift
import SQLClient

let client = SQLClient.shared

// Note: For some Linux/Sybase-mode builds, include the port in the host string
let connected = await client.connect(
    server: "sql.marivil.com:1433",
    username: "sa",
    password: "your-password",
    database: "TestDB"
)

if connected {
    let results = await client.execute("SELECT * FROM Products")
    for table in results {
        for row in table {
            print(row["title"] ?? "No Title")
        }
    }
}
```

### Advanced Configuration

Use `SQLClientConnectionOptions` to tune timeouts, encryption, and more:

```swift
var options = SQLClientConnectionOptions(
    server: "vps.marivil.com",
    username: "sa",
    password: "password"
)
options.port = 1430
options.database = "SwiftTestDb"
options.encryption = .require
options.loginTimeout = 10
options.queryTimeout = 30

let connected = await client.connect(options: options)
```

### Handling Affected Rows

```swift
let result = await client.executeWithResult("UPDATE Products SET price = 19.99 WHERE id = 1")
print("Rows changed: \(result.rowsAffected)")
```

## Environment Variables

The library defaults to **TDS version 7.4** (compatible with SQL Server 2012-2022). You can override this via the `TDSVER` environment variable:

```bash
export TDSVER=7.4
```

## License

MIT License. See [LICENSE](LICENSE) for details.
