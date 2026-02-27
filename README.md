# SQLClient-Swift

[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvkuttyp%2FSQLClient-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/vkuttyp/SQLClient-Swift)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvkuttyp%2FSQLClient-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/vkuttyp/SQLClient-Swift)

A modern, native **Microsoft SQL Server** client for **iOS**, **macOS**, and **Linux** — written in Swift.

Built on top of the open-source [FreeTDS](https://www.freetds.org) library, SQLClient-Swift provides a clean `async/await` API, automatic `Decodable` row mapping, full TLS/encryption support for Azure SQL and SQL Server 2022, and thread safety via Swift's `actor` model.

This is a Swift rewrite and modernisation of [martinrybak/SQLClient](https://github.com/martinrybak/SQLClient), bringing it up to date with FreeTDS 1.5 and modern Swift Concurrency.

---

## Features

- **`async/await` API** — no completion handlers, no callbacks
- **Swift `actor`** — connection state is safe across concurrent callers by design
- **`Decodable` row mapping** — map query results directly to your Swift structs
- **Typed `SQLRow`** — access columns as `String`, `Int`, `Date`, `UUID`, `Decimal`, and more
- **`SQLDataTable` & `SQLDataSet`** — typed, named tables with JSON serialisation and Markdown rendering
- **Full TLS support** — `off`, `request`, `require`, and `strict` (TDS 8.0 / Azure SQL)
- **Windows Authentication** — support for NTLMv2 and Domain-integrated security
- **FreeTDS 1.5** — NTLMv2, read-only AG routing, Kerberos auth, IPv6, cluster failover
- **Affected-row counts** — `rowsAffected` from `INSERT` / `UPDATE` / `DELETE`
- **Remote Procedure Calls (RPC)** — efficient stored procedure execution with full `OUTPUT` parameter and return status support
- **Explicit Transactions** — `beginTransaction()`, `commitTransaction()`, and `rollbackTransaction()`
- **Bulk Copy (BCP)** — high-performance `bulkInsert()` for large data sets
- **Connection Pooling** — built-in `SQLClientPool` for high-concurrency applications
- **Parameterised queries** — built-in SQL injection protection via `?` placeholders or `executeParameterized()`
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
| PKG-Config | 0.29+ (macOS) |
| FreeTDS | 1.0 (1.5 recommended) |

---

## Installation

> **Note for macOS:** If you encounter compilation errors like `'sybdb.h' file not found`, you need to configure `pkg-config` to correctly link your FreeTDS installation. See [PKG-Config Configuration](#pkg-config-configuration) below.

### Swift Package Manager

Add the following to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/vkuttyp/SQLClient-Swift.git", from: "1.1.3")
```

**macOS (Homebrew):**
```bash
brew install freetds
```

**Linux (apt):**
```bash
sudo apt install freetds-dev
```

**iOS / custom build:** Use a pre-compiled `libsybdb.a` (e.g. from [FreeTDS-iOS](https://github.com/patchhf/FreeTDS-iOS)) and link it manually in your Xcode target under **Build Phases → Link Binary With Libraries**, along with `libiconv.tbd`.

### PKG-Config Configuration (macOS)

For systems that do not natively include `pkg-config` or where Homebrew does not provide a `.pc` file for FreeTDS (common on macOS), extra steps are required.

**1. Install pkg-config**

```bash
brew install pkg-config
```

**2. Configure freetds.pc**

A `freetds.pc` file is provided in the `ci/` folder of this repository. You need to make this file available to `pkg-config`.

**Option A: Export PKG_CONFIG_PATH (Recommended)**
Point `pkg-config` to the `ci/` folder in your local copy of this repo:
```bash
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/path/to/SQLClient-Swift/ci"
```

**Option B: Copy to system path**
Copy the file to your system's pkg-config directory:
```bash
cp ci/freetds.pc /usr/local/lib/pkgconfig/
```

**Note on Intel vs Apple Silicon:**
The provided `ci/freetds.pc` is configured for Apple Silicon (`/opt/homebrew`). If you are on an **Intel Mac**, edit the `prefix` line in the file:
- **Apple Silicon:** `prefix=/opt/homebrew/opt/freetds`
- **Intel:** `prefix=/usr/local/opt/freetds`

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

## Connection Pooling

For server-side applications with high concurrency, use `SQLClientPool` to manage a pool of reusable connections:

```swift
let options = SQLClientConnectionOptions(server: "myserver", username: "sa", password: "pwd")
let pool = SQLClientPool(options: options, maxPoolSize: 10)

// Use a client from the pool
try await pool.withClient { client in
    let rows = try await client.query("SELECT GETDATE()")
    print(rows[0])
}

// Disconnect all clients when shutting down
await pool.disconnectAll()
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

#### Windows Authentication (Domain Login)

To connect using Windows credentials, provide the `domain` parameter:

```swift
try await client.connect(
    server:   "myserver",
    username: "windows_user",
    password: "windows_password",
    domain:   "YOUR_DOMAIN"
)
```

#### Advanced Connection Options

Use `SQLClientConnectionOptions` for full control over the connection:

```swift
var options = SQLClientConnectionOptions(server: "myserver")
options.username      = "myuser"
options.password      = "mypassword"
options.database      = "MyDatabase"
options.domain        = "CORP"      // Set domain for Windows Auth
options.port          = 1433
options.encryption    = .strict    // Required for Azure SQL / SQL Server 2022
options.loginTimeout  = 10         // Timeout for establishing connection (seconds)
options.queryTimeout  = 30         // Timeout for statement execution (seconds)
options.readOnly      = true       // ApplicationIntent=ReadOnly (for AG replicas)
options.useNTLMv2     = true       // Default is true
options.networkAuth   = true       // Enable network authentication (trusted connection)
options.useUTF16      = true       // Use UTF-16 for N-types communication

try await client.connect(options: options)
```

### Pre-flight Reachability Check

You can optionally check if the SQL Server port is reachable before attempting a full login. This is useful for failing fast with a clear error:

```swift
try await client.checkReachability(server: "myserver", port: 1433)
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
    
    // Convert the entire row to a dictionary
    let dict = row.toDictionary()
}
```

You can also access columns by zero-based index:

```swift
let firstColumn = row[0]
```

### Querying — `Decodable` Mapping

Map rows directly to your own `Decodable` structs. Column name matching is **case-insensitive** and handles `snake_case` ↔ `camelCase` automatically. It also supports automatic conversion from `String` to primitive types, `Date`, `URL`, and `Decimal`:

```swift
struct UserProfile: Decodable {
    let userID: Int           // matches "user_id" or "UserID"
    let displayName: String   // matches "display_name"
    let website: URL?         // automatically converted from string
    let balance: Decimal      // automatically converted
}

let profiles: [UserProfile] = try await client.query("SELECT * FROM UserProfiles")
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

### Explicit Transactions

Wrap multiple operations in a transaction to ensure atomicity:

```swift
try await client.beginTransaction()
do {
    try await client.run("INSERT INTO Orders ...")
    try await client.run("UPDATE Inventory ...")
    try await client.commitTransaction()
} catch {
    try await client.rollbackTransaction()
    throw error
}
```

### Stored Procedures (RPC)

The `executeRPC` method is the most efficient way to call stored procedures and correctly supports `OUTPUT` parameters and return status:

```swift
let params = [
    SQLParameter(name: "@InVal",  value: 42),
    SQLParameter(name: "@OutVal", value: 0, isOutput: true)
]

let result = try await client.executeRPC("MyStoredProc", parameters: params)

// Access output parameters by name
if let doubled = result.outputParameters["@OutVal"] as? NSNumber {
    print("Doubled value:", doubled.intValue)
}

// Access return status
print("Procedure returned:", result.returnStatus ?? 0)
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

> **Note:** This uses string-level escaping (single-quote doubling). For maximum security or output parameters in ad-hoc queries, use `executeParameterized()`:

```swift
let params = [
    SQLParameter(name: "@UserID", value: 42),
    SQLParameter(name: "@Msg",    value: "Hello World")
]
let result = try await client.executeParameterized(
    "SELECT * FROM Users WHERE ID = @UserID; PRINT @Msg",
    parameters: params
)
```

### Bulk Insert (BCP)

For high-performance loading of thousands of rows, use the Bulk Copy (BCP) interface:

```swift
var rows: [SQLRow] = []
for i in 1...1000 {
    let storage: [(key: String, value: Sendable)] = [
        (key: "ID",   value: i),
        (key: "Name", value: "Bulk User \(i)")
    ]
    rows.append(SQLRow(storage, columnTypes: [:]))
}

let inserted = try await client.bulkInsert(table: "LargeTable", rows: rows)
print("Bulk inserted \(inserted) rows")
```

### SQLDataTable & SQLDataSet

`SQLDataTable` is a typed, named result table — the Swift equivalent of .NET's `DataTable`. Each cell is a strongly-typed `SQLCellValue` enum, the table is `Codable` for JSON serialisation, and it can render itself as a Markdown table.

`SQLDataSet` is a collection of `SQLDataTable` instances, used when a query or stored procedure returns multiple result sets.

#### Fetching a single table

```swift
let table = try await client.dataTable("SELECT * FROM Users")

print(table.rowCount)    // number of rows
print(table.columnCount) // number of columns
```

#### Cell access

```swift
// By row index and column name (case-insensitive)
let cell: SQLCellValue = table[0, "Name"]

// By row and column index
let cell: SQLCellValue = table[0, 0]

// As a typed value
switch table[0, "Age"] {
case .int32(let age): print("Age:", age)
case .null:           print("Age unknown")
default:              break
}

// As Any? for interop with existing code
let raw: Any? = table[0, "Name"].anyValue

// Whole row as a dictionary
let dict: [String: SQLCellValue] = table.row(at: 0)

// All values in a column
let names: [SQLCellValue] = table.column(named: "Name")
```

#### Markdown rendering

```swift
print(table.toMarkdown())
```

Output example:

```
| ID | Name  | Email             |
|---|---|---|
| 1  | Alice | alice@example.com |
| 2  | Bob   | bob@example.com   |
```

#### Decoding rows into a `Decodable` struct

```swift
struct User: Decodable {
    let id: Int
    let name: String
    let email: String
}

let users: [User] = try table.decode()
```

#### JSON serialisation

`SQLDataTable` and `SQLDataSet` are fully `Codable`:

```swift
let json = try JSONEncoder().encode(table)
let restored = try JSONDecoder().decode(SQLDataTable.self, from: json)
```

#### Converting an existing `SQLClientResult`

```swift
let result = try await client.execute("SELECT * FROM Orders")

// First result set as SQLDataTable
let table = result.asDataTable(name: "Orders")

// All result sets as SQLDataSet
let ds = result.asSQLDataSet()
```

#### Multi-table — `SQLDataSet`

Use `dataSet()` when a stored procedure or batch returns more than one result set:

```swift
let ds = try await client.dataSet("EXEC sp_GetDashboard")

// Access by index
let summary = ds[0]

// Access by name (case-insensitive, uses the table name assigned by the procedure)
let details = ds["Details"]

print(ds.count) // number of tables
```

#### Backward compatibility

`SQLDataTable` can be converted back to `[SQLRow]` if you need to pass it to existing code or use `bulkInsert` with a table you just fetched:

```swift
let sqlRows: [SQLRow] = table.toSQLRows()

// Example: fetch from one table and bulk insert into another
let table = try await client.dataTable("SELECT * FROM SourceTable")
try await client.bulkInsert(table: "TargetTable", rows: table.toSQLRows())
```

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

| SQL Server type | Swift type | `SQLCellValue` case |
|---|---|---|
| `tinyint` | `NSNumber` (UInt8) | `.int16` |
| `smallint` | `NSNumber` (Int16) | `.int16` |
| `int` | `NSNumber` (Int32) | `.int32` |
| `bigint` | `NSNumber` (Int64) | `.int64` |
| `bit` | `NSNumber` (Bool) | `.bool` |
| `real` | `NSNumber` (Float) | `.float` |
| `float` | `NSNumber` (Double) | `.double` |
| `decimal`, `numeric` | `NSDecimalNumber` | `.decimal` |
| `money`, `smallmoney` | `NSDecimalNumber` (4 dp) | `.decimal` |
| `char`, `varchar`, `nchar`, `nvarchar` | `String` | `.string` |
| `text`, `ntext`, `xml` | `String` | `.string` |
| `binary`, `varbinary`, `image` | `Data` | `.bytes` |
| `timestamp` | `Data` | `.bytes` |
| `datetime`, `smalldatetime` | `Date` | `.date` |
| `date`, `time`, `datetime2`, `datetimeoffset` | `Date` | `.date` |
| `uniqueidentifier` | `UUID` | `.uuid` |
| `null` | `NSNull` | `.null` |
| `sql_variant`, `cursor`, `table` | ⚠️ Not supported | — |

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

- **Single-space strings:** FreeTDS may return `""` instead of `" "` in some server configurations (upstream FreeTDS bug).
- **`sql_variant`**, **`cursor`**, and **`table`** SQL Server types are not supported.
- **BCP with Unicode:** `bulkInsert` currently works best with standard `VARCHAR` columns.

---

## Credits

- **FreeTDS** — [freetds.org](https://www.freetds.org) · [FreeTDS/freetds](https://github.com/FreeTDS/freetds)
- **Original Objective-C library** — [martinrybak/SQLClient](https://github.com/martinrybak/SQLClient) by Martin Rybak
- **FreeTDS iOS binaries** — [patchhf/FreeTDS-iOS](https://github.com/patchhf/FreeTDS-iOS)

---

## License

SQLClient-Swift is released under the **MIT License**. See [LICENSE](LICENSE) for details.

FreeTDS is licensed under the GNU LGPL. See the [FreeTDS license](https://github.com/FreeTDS/freetds/blob/master/COPYING_LIB.txt) for details.
