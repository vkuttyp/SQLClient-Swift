# SQLClient-Swift

A modern, native **Microsoft SQL Server** client for **iOS**, **macOS**, and **Linux** — written in Swift.

Built on top of the open-source [FreeTDS](https://www.freetds.org) library, SQLClient-Swift provides a clean `async/await` API, automatic `Decodable` row mapping, full TLS/encryption support for Azure SQL and SQL Server 2022, and thread safety via Swift's `actor` model.

This is a Swift rewrite and modernisation of [martinrybak/SQLClient](https://github.com/martinrybak/SQLClient), bringing it up to date with FreeTDS 1.5 and modern Swift Concurrency.

---

## Features

- **`async/await` API** — no completion handlers, no callbacks
- **Swift `actor`** — connection state is safe across concurrent callers by design
- **`Decodable` row mapping** — map query results directly to your Swift structs
- **Typed `SQLRow`** — access columns as `String`, `Int`, `Date`, `UUID`, `Decimal`, and more
- **Full TLS support** — `off`, `request`, `require`, and `strict` (TDS 8.0 / Azure SQL)
- **FreeTDS 1.5** — NTLMv2, read-only AG routing, Kerberos auth, IPv6, cluster failover
- **Affected-row counts** — `rowsAffected` from `INSERT` / `UPDATE` / `DELETE`
- **Parameterised queries** — built-in SQL injection protection via `?` placeholders
- **All SQL Server date types** — `date`, `time`, `datetime2`, `datetimeoffset` as native `Date`
- **Swift Package Manager** — single dependency, no Ruby tooling required

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| iOS | 16.0 |
| macOS | 13.0 |
| tvOS | 16.0 |
| Xcode | 15.0 |
| Swift | 5.9 |
| FreeTDS | 1.0 (1.5 recommended) |

---

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vkuttyp/SQLClient-Swift.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "SQLClientSwift", package: "SQLClient-Swift")
        ]
    )
]
```

Or in Xcode: **File → Add Package Dependencies…** and enter the repository URL.

### Install FreeTDS

SQLClient-Swift wraps FreeTDS — you need the native library present at build time.

**macOS (Homebrew):**
```bash
brew install freetds
```

**Linux (apt):**
```bash
sudo apt install freetds-dev
```

**iOS / custom build:** Use a pre-compiled `libsybdb.a` (e.g. from [FreeTDS-iOS](https://github.com/patchhf/FreeTDS-iOS)) and link it manually in your Xcode target under **Build Phases → Link Binary With Libraries**, along with `libiconv.tbd`.

---

## Quick Start

```swift
import SQLClientSwift

let client = SQLClient.shared

// Connect
try await client.connect(
    server:   "myserver.database.windows.net",
    username: "myuser",
    password: "mypassword",
    database: "MyDatabase"
)

// Query
let rows = try await client.query("SELECT id, name FROM Users")
for row in rows {
    print(row.int("id") ?? 0, row.string("name") ?? "")
}

// Disconnect
await client.disconnect()
```

---

## Usage

### Connecting

The simplest form uses individual parameters:

```swift
try await client.connect(
    server:   "hostname\\instance",   // or "hostname:1433"
    username: "sa",
    password: "secret",
    database: "MyDB"                  // optional
)
```

For advanced options, use `SQLClientConnectionOptions`:

```swift
var options = SQLClientConnectionOptions(
    server:   "myserver.database.windows.net",
    username: "myuser",
    password: "mypassword",
    database: "MyDatabase"
)
options.port          = 1433
options.encryption    = .strict    // required for Azure SQL / SQL Server 2022
options.loginTimeout  = 10        // seconds
options.queryTimeout  = 30        // seconds
options.readOnly      = true      // connect to an Availability Group read replica

try await client.connect(options: options)
```

### Querying — `SQLRow`

`query()` returns `[SQLRow]` from the first result set. Each `SQLRow` provides ordered, typed column access:

```swift
let rows = try await client.query("SELECT * FROM Products")

for row in rows {
    let id:     Int?     = row.int("ProductID")
    let name:   String?  = row.string("Name")
    let price:  Decimal? = row.decimal("Price")
    let added:  Date?    = row.date("DateAdded")
    let sku:    UUID?    = row.uuid("SKU")
    let thumb:  Data?    = row.data("Thumbnail")
    let active: Bool?    = row.bool("IsActive")

    if row.isNull("DiscontinuedDate") {
        print("\(name ?? "") is still available")
    }
}
```

You can also access columns by zero-based index:

```swift
let firstColumn = row[0]
```

### Querying — `Decodable` Mapping

Map rows directly to your own `Decodable` structs. Column name matching is **case-insensitive** and handles `snake_case` ↔ `camelCase` automatically:

```swift
struct Product: Decodable {
    let productID: Int
    let name: String
    let price: Decimal
    let dateAdded: Date
}

// "product_id", "ProductID", and "productId" all match the `productID` property
let products: [Product] = try await client.query(
    "SELECT product_id, name, price, date_added FROM Products"
)
```

### Executing — `SQLClientResult`

`execute()` returns a `SQLClientResult` containing all result sets and the affected-row count. Use this when running multi-statement batches or when you need `rowsAffected`:

```swift
let result = try await client.execute("""
    SELECT * FROM Orders WHERE Status = 'Open';
    SELECT COUNT(*) AS Total FROM Orders;
""")

let openOrders = result.tables[0]          // first result set
let countRow   = result.tables[1].first    // second result set
print("Total orders:", countRow?.int("Total") ?? 0)
```

### DML — INSERT, UPDATE, DELETE

Use `run()` for data-modification statements. It returns the number of affected rows:

```swift
let affected = try await client.run(
    "UPDATE Users SET LastLogin = GETDATE() WHERE UserID = 42"
)
print("\(affected) row(s) updated")
```

### Parameterised Queries

Use `?` placeholders to pass values safely. Strings are automatically escaped to prevent SQL injection:

```swift
// SELECT with parameters
let rows = try await client.execute(
    "SELECT * FROM Users WHERE Name = ? AND Active = ?",
    parameters: ["O'Brien", true]
)

// INSERT with parameters
try await client.run(
    "INSERT INTO Log (UserID, Message, CreatedAt) VALUES (?, ?, ?)",
    parameters: [42, "Logged in", Date()]
)

// NULL parameter
try await client.run(
    "UPDATE Users SET ManagerID = ? WHERE UserID = ?",
    parameters: [nil, 7]
)
```

> **Note:** This uses string-level escaping (single-quote doubling). For maximum security with untrusted user input, prefer stored procedures.

### Error Handling

All errors are thrown as `SQLClientError`, which conforms to `LocalizedError`:

```swift
do {
    try await client.connect(server: "badhost", username: "sa", password: "wrong")
} catch SQLClientError.connectionFailed(let server) {
    print("Could not reach \(server)")
} catch SQLClientError.alreadyConnected {
    print("Already connected — call disconnect() first")
} catch {
    print("Error:", error.localizedDescription)
}
```

| Error case | When thrown |
|---|---|
| `.alreadyConnected` | `connect()` called while already connected |
| `.notConnected` | `execute()` or `query()` called before connecting |
| `.loginAllocationFailed` | FreeTDS internal allocation failure |
| `.connectionFailed(server:)` | TCP connection or login rejected by the server |
| `.databaseSelectionFailed(_)` | `USE <database>` command failed |
| `.executionFailed` | `dbsqlexec()` returned an error |
| `.noCommandText` | An empty SQL string was passed |

### Server Messages

Informational messages from SQL Server (`PRINT`, low-severity `RAISERROR`) are delivered via `NotificationCenter` rather than thrown, since they are non-fatal:

```swift
NotificationCenter.default.addObserver(
    forName: .SQLClientMessage,
    object: nil,
    queue: .main
) { notification in
    let code     = notification.userInfo?[SQLClientMessageKey.code]     as? Int    ?? 0
    let message  = notification.userInfo?[SQLClientMessageKey.message]  as? String ?? ""
    let severity = notification.userInfo?[SQLClientMessageKey.severity] as? Int    ?? 0
    print("Server message [\(severity)] #\(code): \(message)")
}
```

---

## Encryption & Azure SQL

| Mode | Description | Use when |
|---|---|---|
| `.off` | No TLS | On-premise, fully trusted network |
| `.request` | Opportunistic TLS *(default)* | General on-premise use |
| `.require` | Always encrypt, skip cert validation | Self-signed certificates |
| `.strict` | TDS 8.0 — always encrypt, validate cert | **Azure SQL, SQL Server 2022** |

For **Azure SQL Database** or any server with forced encryption enabled:

```swift
var options = SQLClientConnectionOptions(
    server:   "yourserver.database.windows.net",
    username: "myuser",
    password: "mypassword"
)
options.encryption = .strict
try await client.connect(options: options)
```

---

## Type Mapping

| SQL Server type | Swift type |
|---|---|
| `tinyint` | `NSNumber` (UInt8) |
| `smallint` | `NSNumber` (Int16) |
| `int` | `NSNumber` (Int32) |
| `bigint` | `NSNumber` (Int64) |
| `bit` | `NSNumber` (Bool) |
| `real` | `NSNumber` (Float) |
| `float` | `NSNumber` (Double) |
| `decimal`, `numeric` | `NSDecimalNumber` |
| `money`, `smallmoney` | `NSDecimalNumber` (4 decimal places) |
| `char`, `varchar`, `nchar`, `nvarchar` | `String` |
| `text`, `ntext`, `xml` | `String` |
| `binary`, `varbinary`, `image` | `Data` |
| `timestamp` | `Data` |
| `datetime`, `smalldatetime` | `Date` |
| `date`, `time`, `datetime2`, `datetimeoffset` | `Date` (TDS 7.3+) or `String` (TDS 7.1) |
| `uniqueidentifier` | `UUID` |
| `null` | `NSNull` |
| `sql_variant`, `cursor`, `table` | ⚠️ Not supported |

> **Date types note:** `date`, `time`, `datetime2`, and `datetimeoffset` are returned as `Date` when using TDS 7.3 or higher. FreeTDS 1.x defaults to `auto` protocol negotiation, which will select 7.3+ automatically for modern SQL Server versions. If you see strings instead of dates on an older server, set the `TDSVER` environment variable in your Xcode scheme to `7.3` or `auto`.

---

## Configuration

### Max Text Size

Controls the maximum bytes returned for `TEXT`, `NTEXT`, and `VARCHAR(MAX)` columns. Default is 4096 bytes.

```swift
// In your setup code, before connecting:
SQLClient.shared.maxTextSize = 65536
```

### TDS Protocol Version

Set the `TDSVER` environment variable in your Xcode scheme (**Edit Scheme → Run → Arguments → Environment Variables**):

| Value | Protocol | Compatible with |
|---|---|---|
| `auto` | Autodetect *(recommended)* | All SQL Server versions |
| `7.4` | TDS 7.4 | SQL Server 2012+ |
| `7.3` | TDS 7.3 | SQL Server 2008 |
| `7.2` | TDS 7.2 | SQL Server 2005 |
| `7.1` | TDS 7.1 | SQL Server 2000 |

---

## Known Limitations

- **Stored procedure OUTPUT parameters** are not yet supported. Stored procedures that return result sets via `SELECT` work normally.
- **Connection pooling** is not built in. For high-concurrency server-side apps, create multiple `SQLClient` instances manually.
- **Single-space strings:** FreeTDS may return `""` instead of `" "` in some server configurations (upstream FreeTDS bug).
- **`sql_variant`**, **`cursor`**, and **`table`** SQL Server types are not supported.

---

## Credits

- **FreeTDS** — [freetds.org](https://www.freetds.org) · [FreeTDS/freetds](https://github.com/FreeTDS/freetds)
- **Original Objective-C library** — [martinrybak/SQLClient](https://github.com/martinrybak/SQLClient) by Martin Rybak
- **FreeTDS iOS binaries** — [patchhf/FreeTDS-iOS](https://github.com/patchhf/FreeTDS-iOS)

---

## License

SQLClient-Swift is released under the **MIT License**. See [LICENSE](LICENSE) for details.

FreeTDS is licensed under the GNU LGPL. See the [FreeTDS license](https://github.com/FreeTDS/freetds/blob/master/COPYING_LIB.txt) for details.
