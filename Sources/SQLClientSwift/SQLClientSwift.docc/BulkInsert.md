# Bulk Insert (BCP)

High-performance insertion of large datasets using the Bulk Copy (BCP) protocol.

## Overview

The Bulk Copy (BCP) interface is significantly faster than standard `INSERT` statements when loading thousands of rows. SQLClient provides a simple `bulkInsert` method that leverages the underlying FreeTDS BCP implementation.

### Usage

To perform a bulk insert, prepare an array of ``SQLRow`` objects and specify the target table name.

```swift
var rows: [SQLRow] = []
for i in 1...1000 {
    let storage: [(key: String, value: Sendable)] = [
        (key: "Id", value: i),
        (key: "Name", value: "User \(i)")
    ]
    rows.append(SQLRow(storage, columnTypes: [:]))
}

let insertedCount = try await client.bulkInsert(table: "Users", rows: rows)
print("Successfully inserted \(insertedCount) rows.")
```

### Considerations

- **Encoding**: Currently, BCP works best with standard `VARCHAR` columns.
- **Table Existence**: The target table must exist in the database before calling `bulkInsert`.
- **Permissions**: The database user must have the necessary permissions to perform bulk operations.

## Methods

- ``SQLClient/bulkInsert(table:rows:)``
