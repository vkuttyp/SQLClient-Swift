# ``SQLClientSwift``

A modern, native Microsoft SQL Server client for iOS, macOS, and Linux — written in Swift.

## Overview

SQLClient-Swift provides a clean, asynchronous API for interacting with SQL Server databases. It is built on top of the open-source FreeTDS library, offering a high-performance and reliable connection layer.

### Key Features

- **Native Support**: Works on all Apple platforms and Linux.
- **Modern API**: Leverages Swift's `async/await` for asynchronous operations.
- **Type Safety**: Automatic mapping of database rows to Swift `Decodable` types.
- **Thread Safety**: Uses Swift actors to ensure safe concurrent access to database connections.
- **Full Encryption Support**: Supports TLS/SSL for Azure SQL and modern SQL Server instances.

## Topics

### Essentials

- ``SQLClient``
- ``SQLClientConnectionOptions``
- ``SQLClientResult``
- ``SQLRow``
