#if FREETDS_FOUND
import CFreeTDS
import Foundation

extension SQLClient {
    /// High-performance bulk insert of rows into a table.
    /// Rows must match the table schema exactly in order and type.
    public func bulkInsert(table: String, rows: [SQLRow]) async throws -> Int {
        await awaitPrevious()
        guard self.isConnected else { throw SQLClientError.notConnected }
        guard !rows.isEmpty else { return 0 }

        guard let conn = self.connectionHandle else { throw SQLClientError.notConnected }
        let handle = TDSHandle(pointer: conn)

        let task: Task<Int, Error> = Task {
            return try await self.runBlocking {
                return try self._bulkInsertSync(table: table, rows: rows, connection: handle)
            }
        }
        setActiveTask(Task { _ = await task.result })
        return try await task.value
    }

    private nonisolated func _bulkInsertSync(table: String, rows: [SQLRow], connection: TDSHandle) throws -> Int {
        let conn = connection.pointer
        dbcancel(conn)

        // bcp_init direction: DB_IN
        guard bcp_init(conn, table, nil, nil, 1) != FAIL else {
            throw SQLClientError.executionFailed(detail: self.getLastError())
        }

        guard let firstRow = rows.first else { return 0 }
        let columns = firstRow.columns
        let numCols = columns.count

        // Pre-allocate buffers for each column
        let bufSize = 8192
        var colBuffers: [UnsafeMutableRawPointer] = []
        for _ in 0..<numCols {
            colBuffers.append(UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 1))
        }
        defer { for buf in colBuffers { buf.deallocate() } }

        // Bind columns
        for (i, _) in columns.enumerated() {
            let colIdx = Int32(i + 1)
            // bcp_bind: type 47=SYBCHAR
            guard bcp_bind(conn, colBuffers[i].assumingMemoryBound(to: BYTE.self), 0, -1, nil, 0, 47, colIdx) != FAIL else {
                throw SQLClientError.executionFailed(detail: self.getLastError())
            }
        }

        var totalInserted = 0
        for row in rows {
            for (i, col) in columns.enumerated() {
                let val = row[col]
                let str = (val is NSNull) ? "" : "\(val ?? "")"
                let utf8 = str.utf8
                let count = min(utf8.count, bufSize - 1)
                
                let bytes = colBuffers[i].assumingMemoryBound(to: UInt8.self)
                for (j, b) in utf8.enumerated() {
                    if j >= count { break }
                    bytes[j] = b
                }
                bytes[count] = 0

                // Update the length for the current row
                bcp_collen(conn, DBINT(count), Int32(i + 1))
            }

            guard bcp_sendrow(conn) != FAIL else {
                throw SQLClientError.executionFailed(detail: self.getLastError())
            }
            totalInserted += 1
        }

        let result = bcp_done(conn)
        guard result != -1 else {
            throw SQLClientError.executionFailed(detail: self.getLastError())
        }

        return Int(result)
    }
}
#endif
