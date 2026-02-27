#if FREETDS_FOUND
import CFreeTDS
import Foundation

extension SQLClient {
    /// Executes a stored procedure using the RPC (Remote Procedure Call) interface.
    /// This is more efficient than string-building and correctly handles output parameters.
    public func executeRPC(_ name: String, parameters: [SQLParameter] = []) async throws -> SQLClientResult {
        await awaitPrevious()
        guard self.isConnected else { throw SQLClientError.notConnected }

        guard let conn = self.connectionHandle else { throw SQLClientError.notConnected }
        let handle = TDSHandle(pointer: conn)

        let task: Task<SQLClientResult, Error> = Task {
            return try await self.runBlocking {
                return try self._executeRPCSync(name: name, parameters: parameters, connection: handle)
            }
        }
        setActiveTask(Task { _ = await task.result })
        return try await task.value
    }

    private nonisolated func _executeRPCSync(name: String, parameters: [SQLParameter], connection: TDSHandle) throws -> SQLClientResult {
        let conn = connection.pointer
        dbcancel(conn)

        // Init RPC
        guard dbrpcinit(conn, name, 0) != FAIL else {
            throw SQLClientError.executionFailed(detail: self.getLastError())
        }

        // Keep pointers alive during the call
        var buffers: [(UnsafeMutableRawPointer, Int32)] = []
        defer { for (ptr, _) in buffers { ptr.deallocate() } }

        for param in parameters {
            let status: BYTE = param.isOutput ? BYTE(DBRPCRETURN) : 0
            let type = rpcType(for: param.value)
            let (ptr, len) = rpcValue(for: param.value, type: type, isOutput: param.isOutput)
            buffers.append((ptr, len))

            let maxLen: DBINT = param.isOutput ? 8000 : -1 // Max size for output params

            guard dbrpcparam(conn, param.name, status, type, maxLen, DBINT(len), ptr.assumingMemoryBound(to: BYTE.self)) != FAIL else {
                throw SQLClientError.executionFailed(detail: self.getLastError())
            }
        }

        guard dbrpcsend(conn) != FAIL else {
            throw SQLClientError.executionFailed(detail: self.getLastError())
        }
        guard dbsqlok(conn) != FAIL else {
            throw SQLClientError.executionFailed(detail: self.getLastError())
        }

        // Process results
        var tables: [[SQLRow]] = []
        var totalAffected: Int = -1
        var outputParams: [String: Sendable] = [:]
        var returnStatus: Int?
        var resultCode = dbresults(conn)

        while resultCode != NO_MORE_RESULTS && resultCode != FAIL {
            let count = Int(dbcount(conn))
            if count >= 0 { totalAffected = totalAffected < 0 ? count : totalAffected + count }
            let numCols = Int(dbnumcols(conn))
            var table: [SQLRow] = []

            if numCols > 0 {
                var colMeta: [(name: String, type: Int32)] = []
                var columnTypes: [String: Int32] = [:]
                for i in 1...numCols {
                    let name = String(cString: dbcolname(conn, Int32(i)))
                    let type = dbcoltype(conn, Int32(i))
                    colMeta.append((name: name, type: type))
                    columnTypes[name] = type
                }
                while true {
                    let rowCode = dbnextrow(conn)
                    if rowCode == NO_MORE_ROWS || rowCode == FAIL { break }
                    if rowCode == BUF_FULL { continue }

                    var storage: [(key: String, value: Sendable)] = []
                    for (idx, col) in colMeta.enumerated() {
                        let colIdx = Int32(idx + 1)
                        storage.append((key: col.name, value: columnValue(conn: conn, column: colIdx, type: col.type)))
                    }
                    table.append(SQLRow(storage, columnTypes: columnTypes))
                }
            }
            if !table.isEmpty {
                tables.append(table)
            }
            
            // Check for output parameters and return status after each result set
            let numRets = Int(dbnumrets(conn))
            if numRets > 0 {
                for i in 1...numRets {
                    let idx = Int32(i)
                    if let namePtr = dbretname(conn, idx) {
                        let name = String(cString: namePtr)
                        let type = dbrettype(conn, idx)
                        outputParams[name] = returnValue(conn: conn, index: idx, type: type)
                    }
                }
            }
            if dbhasretstat(conn) != 0 {
                returnStatus = Int(dbretstatus(conn))
            }

            resultCode = dbresults(conn)
        }

        return SQLClientResult(tables: tables, rowsAffected: totalAffected, outputParameters: outputParams, returnStatus: returnStatus)
    }

    private nonisolated func rpcType(for value: Sendable?) -> Int32 {
        guard let value = value else { return 31 } // SYBVOID
        switch value {
        case is Int, is Int32: return 56 // SYBINT4
        case is Int16: return 52        // SYBINT2
        case is Int64: return 127       // SYBINT8
        case is Float: return 59        // SYBREAL
        case is Double: return 62       // SYBFLT8
        case is Bool: return 50         // SYBBIT
        case is String: return 39       // SYBVARCHAR
        case is Data: return 37         // SYBVARBINARY
        case is Date: return 61         // SYBDATETIME
        case is UUID: return 36         // SYBUNIQUE
        default: return 39              // Default to string
        }
    }

    private nonisolated func rpcValue(for value: Sendable?, type: Int32, isOutput: Bool) -> (UnsafeMutableRawPointer, Int32) {
        let ptr: UnsafeMutableRawPointer
        var len: Int32 = 0

        switch Int(type) {
        case 56: // SYBINT4
            ptr = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 4)
            len = 4
            if let v = (value as? NSNumber)?.int32Value { ptr.storeBytes(of: v, as: Int32.self) }
        case 52: // SYBINT2
            ptr = UnsafeMutableRawPointer.allocate(byteCount: 2, alignment: 2)
            len = 2
            if let v = (value as? NSNumber)?.int16Value { ptr.storeBytes(of: v, as: Int16.self) }
        case 127: // SYBINT8
            ptr = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
            len = 8
            if let v = (value as? NSNumber)?.int64Value { ptr.storeBytes(of: v, as: Int64.self) }
        case 50: // SYBBIT
            ptr = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
            len = 1
            if let v = (value as? NSNumber)?.boolValue { ptr.storeBytes(of: v ? UInt8(1) : UInt8(0), as: UInt8.self) }
        case 39: // SYBVARCHAR
            let str = (value as? String) ?? ""
            let utf8 = str.utf8
            ptr = UnsafeMutableRawPointer.allocate(byteCount: utf8.count + 1, alignment: 1)
            len = Int32(utf8.count)
            let bytes = ptr.assumingMemoryBound(to: UInt8.self)
            for (i, b) in utf8.enumerated() { bytes[i] = b }
            bytes[utf8.count] = 0
        case 37: // SYBVARBINARY
            let data = (value as? Data) ?? Data()
            ptr = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 1)
            len = Int32(data.count)
            data.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: data.count)
        default:
            ptr = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
            len = 1
        }
        return (ptr, len)
    }
}
#endif
