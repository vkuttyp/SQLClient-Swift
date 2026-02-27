# Transactions

Execute multiple SQL statements within a single atomic transaction.

## Overview

SQLClient allows you to explicitly manage database transactions using the `beginTransaction`, `commitTransaction`, and `rollbackTransaction` methods. This ensures that a group of operations either all succeed or all fail together, maintaining data integrity.

### Usage

```swift
try await client.beginTransaction()
do {
    try await client.run("INSERT INTO Orders (Id, Total) VALUES (1, 100)")
    try await client.run("UPDATE Inventory SET Stock = Stock - 1 WHERE ProductId = 5")
    
    // Commit the changes to the database
    try await client.commitTransaction()
} catch {
    // If any operation fails, roll back the entire transaction
    try await client.rollbackTransaction()
    throw error
}
```

## Methods

- ``SQLClient/beginTransaction()``
- ``SQLClient/commitTransaction()``
- ``SQLClient/rollbackTransaction()``
