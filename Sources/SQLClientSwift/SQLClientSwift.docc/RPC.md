# Stored Procedures (RPC)

Execute stored procedures efficiently using Remote Procedure Calls (RPC).

## Overview

Remote Procedure Calls are the native way to execute stored procedures in SQL Server. Unlike building an `EXEC` string, RPC correctly handles input and output parameters, return statuses, and is generally more efficient.

### Usage

To call a stored procedure, use the `executeRPC` method along with an array of ``SQLParameter`` objects.

```swift
let params = [
    SQLParameter(name: "@InVal", value: 42),
    SQLParameter(name: "@OutVal", value: 0, isOutput: true)
]

let result = try await client.executeRPC("MyProcedure", parameters: params)

// Access output parameters
if let resultVal = result.outputParameters["@OutVal"] as? NSNumber {
    print("Result from procedure: \(resultVal.intValue)")
}

// Access return status
if let status = result.returnStatus {
    print("Procedure returned status: \(status)")
}
```

### Advantages of RPC

- **Type Safety**: Parameters are passed with their native types.
- **Output Parameters**: Built-in support for capturing values from `OUTPUT` parameters.
- **Performance**: Skips some of the parsing overhead associated with ad-hoc T-SQL.

## Related Types

- ``SQLParameter``
- ``SQLClientResult/outputParameters``
- ``SQLClientResult/returnStatus``

## Methods

- ``SQLClient/executeRPC(_:parameters:)``
