// SQLClient.swift (v2 - modern Swift Concurrency rewrite)
// Updated for Swift 6 strict concurrency and FreeTDS compatibility.

import Foundation
import CFreeTDS

// MARK: - Notification Names

public extension Notification.Name {
    static let SQLClientMessage = Notification.Name("SQLClientMessageNotification")
}

public enum SQLClientMessageKey {
    public static let code     = "code"
    public static let message  = "message"
    public static let severity = "severity"
}

// MARK: - Errors

public enum SQLClientError: Error, LocalizedError {
    case alreadyConnected
    case notConnected
    case loginAllocationFailed
    case connectionFailed(server: String)
    case databaseSelectionFailed(String)
    case executionFailed
    case noCommandText
    case parameterCountMismatch

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:        return "Already connected to a server. Call disconnect() first."
        case .notConnected:            return "Not connected. Call connect() before executing queries."
        case .loginAllocationFailed:   return "FreeTDS could not allocate a login record."
        case .connectionFailed(let s): return "Could not connect to '\(s)'."
        case .databaseSelectionFailed(let db): return "Could not select database '\(db)'."
        case .executionFailed:         return "SQL execution failed. Check SQLClientMessage notifications for details."
        case .noCommandText:           return "SQL command string was empty."
        case .parameterCountMismatch:  return "Number of parameters does not match number of placeholders."
        }
    }
}

// MARK: - Encryption

public enum SQLClientEncryption: String, Sendable {
    case off     = "off"
    case request = "request"
    case require = "require"
    case strict  = "strict"
}

// MARK: - Connection Options

public struct SQLClientConnectionOptions: Sendable {
    public var server:       String
    public var username:     String
    public var password:     String
    public var database:     String?
    public var port:         UInt16?
    public var encryption:   SQLClientEncryption = .request
    public var useNTLMv2:    Bool = true
    public var networkAuth:  Bool = false
    public var readOnly:     Bool = false
    public var useUTF16:     Bool = false
    public var queryTimeout: Int  = 0
    public var loginTimeout: Int  = 0

    public init(server: String, username: String, password: String, database: String? = nil) {
        self.server   = server
        self.username = username
        self.password = password
        self.database = database
    }
}

// MARK: - Result Types

public struct SQLRow: Sendable {
    private let storage: [(key: String, value: Sendable)]
    internal let columnTypes: [String: Int32]
    
    internal init(_ dict: [(key: String, value: Sendable)], columnTypes: [String: Int32]) {
        self.storage = dict
        self.columnTypes = columnTypes
    }
    
    public var columns: [String] { storage.map(\.key) }
    
    public subscript(column: String) -> Sendable? {
        storage.first(where: { $0.key == column })?.value
    }
    
    public subscript(index: Int) -> Sendable? {
        guard index >= 0 && index < storage.count else { return nil }
        return storage[index].value
    }
    
    public func string(_ column: String)  -> String?  { self[column] as? String }
    public func int(_ column: String)     -> Int?     { (self[column] as? NSNumber)?.intValue }
    public func int64(_ column: String)   -> Int64?   { (self[column] as? NSNumber)?.int64Value }
    public func double(_ column: String)  -> Double?  { (self[column] as? NSNumber)?.doubleValue }
    public func bool(_ column: String)    -> Bool?    { (self[column] as? NSNumber)?.boolValue }
    public func date(_ column: String)    -> Date?    { self[column] as? Date }
    public func data(_ column: String)    -> Data?    { self[column] as? Data }
    public func decimal(_ column: String) -> Decimal? { (self[column] as? NSDecimalNumber)?.decimalValue }
    public func uuid(_ column: String)    -> UUID?    { self[column] as? UUID }
    public func isNull(_ column: String)  -> Bool     { self[column] is NSNull }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for item in storage {
            dict[item.key] = item.value
        }
        return dict
    }
}

public struct SQLClientResult: Sendable {
    public let tables: [[SQLRow]]
    public let rowsAffected: Int
    public var rows: [SQLRow] { tables.first ?? [] }
}

// MARK: - Sendable Pointer Wrapper

private struct TDSHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

// MARK: - SQLClient Actor

public actor SQLClient {
    public static let shared = SQLClient()
    
    private static let initializeFreeTDS: Void = {
        dbinit()
        dberrhandle(SQLClient_errorHandler)
        dbmsghandle(SQLClient_messageHandler)
    }()

    public init() {
        _ = SQLClient.initializeFreeTDS
    }

    private let queue = DispatchQueue(label: "com.sqlclient.serial")
    private var activeTask: Task<Void, Never>?

    private func awaitPrevious() async {
        _ = await activeTask?.result
    }

    public var maxTextSize: Int = 4096
    private var login:      OpaquePointer?
    private var connection: OpaquePointer?
    private var connected   = false

    public func connect(server: String, username: String, password: String, database: String? = nil) async throws {
        try await connect(options: SQLClientConnectionOptions(server: server, username: username, password: password, database: database))
    }

   public func connect(options: SQLClientConnectionOptions) async throws {
    await awaitPrevious()
    
    guard !self.connected else { throw SQLClientError.alreadyConnected }
    
    let result: (login: TDSHandle, connection: TDSHandle) = try await {
        let task: Task<(login: TDSHandle, connection: TDSHandle), Error> = Task {
            return try await self.runBlocking {
                return try self._connectSync(options: options)
            }
        }
        activeTask = Task { _ = await task.result }
        return try await task.value
    }()
    
    self.login = result.login.pointer
    self.connection = result.connection.pointer
    self.connected = true
   }

    public func disconnect() async {
        await awaitPrevious()
        
        guard self.connected else { return }
        let lgn = self.login.map { TDSHandle(pointer: $0) }
        let conn = self.connection.map { TDSHandle(pointer: $0) }
        
        let task: Task<Void, Never> = Task {
            await self.runBlockingVoid {
                self._disconnectSync(login: lgn, connection: conn)
            }
        }
        activeTask = task
        await task.value
        
        self.login = nil
        self.connection = nil
        self.connected = false
    }

    public func execute(_ sql: String) async throws -> SQLClientResult {
        await awaitPrevious()
        
        guard self.connected, let conn = self.connection else { throw SQLClientError.notConnected }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SQLClientError.noCommandText }
        let maxText = self.maxTextSize
        let handle = TDSHandle(pointer: conn)
        
        let task: Task<SQLClientResult, Error> = Task {
            return try await self.runBlocking {
                return try self._executeSync(sql: sql, connection: handle, maxTextSize: maxText)
            }
        }
        activeTask = Task { _ = await task.result }
        return try await task.value
    }

    public func query(_ sql: String) async throws -> [SQLRow] { try await execute(sql).rows }

    public func query<T: Decodable>(_ sql: String, as type: T.Type = T.self) async throws -> [T] {
        let rows = try await query(sql)
        return try rows.map { try T(from: SQLRowDecoder(row: $0)) }
    }

    @discardableResult
    public func run(_ sql: String) async throws -> Int { try await execute(sql).rowsAffected }

    public func execute(_ sql: String, parameters: [Any?]) async throws -> SQLClientResult {
        let built = try SQLClient.buildSQL(sql, parameters: parameters)
        return try await execute(built)
    }

    public var isConnected: Bool { connected }

    // MARK: - Synchronous Helpers

// MARK: - Reachability

    /// Optional pre-flight TCP check. Call this before connect() if you want
    /// to fail fast with a clear error instead of waiting for FreeTDS to time out.
    /// Not called automatically — integrate tests and CI skip it safely this way.
    public func checkReachability(server: String, port: UInt16 = 1433) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        queue.async {
            var readStream:  Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocketToHost(
                nil, server as CFString, UInt32(port),
                &readStream, &writeStream
            )
            guard let read  = readStream?.takeRetainedValue(),
                  let write = writeStream?.takeRetainedValue() else {
                cont.resume(throwing: SQLClientError.connectionFailed(server: server))
                return
            }
            CFReadStreamOpen(read)
            CFWriteStreamOpen(write)

            let deadline = Date().addingTimeInterval(5)
            var connected = false
            while Date() < deadline {
                if CFReadStreamGetStatus(read)  == .open &&
                   CFWriteStreamGetStatus(write) == .open {
                    connected = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            CFReadStreamOpen(read)
            CFWriteStreamOpen(write)

            if connected {
                cont.resume()
            } else {
                cont.resume(throwing: SQLClientError.connectionFailed(server: server))
            }
        }
    }
}

    private nonisolated func _connectSync(options: SQLClientConnectionOptions) throws -> (login: TDSHandle, connection: TDSHandle) {
        guard let lgn = dblogin() else { throw SQLClientError.loginAllocationFailed }

        dbsetlname(lgn, options.username, 2) // DBSETUSER
        dbsetlname(lgn, options.password, 3) // DBSETPWD
        dbsetlname(lgn, "SQLClientSwift", 5) // DBSETAPP
        
        // Ensure we get UTF-8 from the server for N-types
        dbsetlname(lgn, "UTF-8", 10) // DBSETCHARSET

        if let port = options.port { dbsetlshort(lgn, Int32(port), 1006) } // DBSETPORT
        if options.encryption != .request { dbsetlname(lgn, options.encryption.rawValue, 1005) } // DBSETENCRYPTION
        dbsetlbool(lgn, options.useNTLMv2 ? 1 : 0, 1002) // DBSETNTLMV2
        if options.networkAuth { dbsetlbool(lgn, 1, 101) } // DBSETNETWORKAUTH
        if options.readOnly { dbsetlbool(lgn, 1, 1003) } // DBSETREADONLY
        if options.useUTF16 { dbsetlbool(lgn, 1, 1001) } // DBSETUTF16
        if options.loginTimeout > 0 { dbsetlogintime(Int32(options.loginTimeout)) }

        guard let conn = dbopen(lgn, options.server) else {
            dbloginfree(lgn)
            throw SQLClientError.connectionFailed(server: options.server)
        }

        if let db = options.database, !db.isEmpty {
            guard dbuse(conn, db) != FAIL else {
                dbclose(conn)
                dbloginfree(lgn)
                throw SQLClientError.databaseSelectionFailed(db)
            }
        }
        
        return (TDSHandle(pointer: lgn), TDSHandle(pointer: conn))
    }

    private nonisolated func _disconnectSync(login: TDSHandle?, connection: TDSHandle?) {
        if let c = connection?.pointer { dbclose(c) }
        if let l = login?.pointer { dbloginfree(l) }
    }

    private nonisolated func _executeSync(sql: String, connection: TDSHandle, maxTextSize: Int) throws -> SQLClientResult {
        let conn = connection.pointer
        
        // Ensure any previous results are cancelled before a new command
        dbcancel(conn)
        
        _ = dbsetopt(conn, DBTEXTSIZE, "\(maxTextSize)", -1)
        
        guard dbcmd(conn, sql) != FAIL, dbsqlexec(conn) != FAIL else { throw SQLClientError.executionFailed }

        var tables: [[SQLRow]] = []
        var totalAffected: Int = -1
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
            tables.append(table)
            resultCode = dbresults(conn)
        }
        return SQLClientResult(tables: tables, rowsAffected: totalAffected)
    }

    private nonisolated func columnValue(conn: OpaquePointer, column: Int32, type: Int32) -> Sendable {
        guard let dataPtr = dbdata(conn, column) else { return NSNull() }
        let len = dbdatlen(conn, column)
        guard len > 0 else { return NSNull() }
        
        let data = UnsafeRawPointer(dataPtr)

        switch Int(type) {
        case 48: // SYBINT1
            return NSNumber(value: data.load(as: UInt8.self))
        case 52: // SYBINT2
            return NSNumber(value: data.loadUnaligned(as: Int16.self))
        case 56: // SYBINT4
            return NSNumber(value: data.loadUnaligned(as: Int32.self))
        case 127: // SYBINT8
            return NSNumber(value: data.loadUnaligned(as: Int64.self))
        case 59: // SYBREAL
            return NSNumber(value: data.loadUnaligned(as: Float.self))
        case 62: // SYBFLT8
            return NSNumber(value: data.loadUnaligned(as: Double.self))
        case 50, 104: // SYBBIT, SYBBITN
            return NSNumber(value: data.load(as: UInt8.self) != 0)
        case 47, 39, 102, 103, 35, 99, 241: // SYBCHAR, SYBVARCHAR, SYBTEXT, SYBNTEXT, SYBXML, SYBNCHAR, SYBNVARCHAR
            let buf = UnsafeBufferPointer<UInt8>(start: data.assumingMemoryBound(to: UInt8.self), count: Int(len))
            // Try UTF-8 first, then windowsCP1252 as fallback
            if let str = String(bytes: buf, encoding: .utf8) { return str }
            if let str = String(bytes: buf, encoding: .windowsCP1252) { return str }
            // If it's UCS-2 (type 103/SYBNVARCHAR usually), try UTF-16
            if let str = String(bytes: buf, encoding: .utf16LittleEndian) { return str }
            return ""
        case 45, 37, 34, 173, 174, 167: // SYBBINARY, SYBVARBINARY, SYBIMAGE, SYBBIGBINARY, SYBBIGVARBINARY, SYBBLOB
            return Data(bytes: dataPtr, count: Int(len))
        case 61, 58, 111: // SYBDATETIME, SYBDATETIME4, SYBDATETIMN
            return legacyDate(conn: conn, type: type, data: data, len: len)
        case 40, 41, 42, 43, 187, 188: // SYBMSDATE, SYBMSTIME, SYBMSDATETIME2, SYBMSDATETIMEOFFSET, SYBBIGDATETIME, SYBBIGTIME
            return msDateTime(conn: conn, type: type, data: data, len: len)
        case 55, 63, 60, 122, 110, 106, 108: // SYBDECIMAL, SYBNUMERIC, SYBMONEY, SYBMONEY4, SYBMONEYN, SYBDECIMALN, SYBNUMERICN
            return convertToDecimal(conn: conn, type: type, data: data, len: len)
        case 36: // SYBUNIQUE
            guard len == 16 else { return NSNull() }
            var bytes = [UInt8](repeating: 0, count: 16)
            memcpy(&bytes, dataPtr, 16)
            
            // SQL Server UniqueIdentifier mixed-endian -> RFC 4122 Big-Endian
            let swapped: [UInt8] = [
                bytes[3], bytes[2], bytes[1], bytes[0],
                bytes[5], bytes[4],
                bytes[7], bytes[6],
                bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ]
            return NSUUID(uuidBytes: swapped) as UUID
        case 31: // SYBVOID
            return NSNull()
        default:
            return Data(bytes: dataPtr, count: Int(len))
        }
    }

    private nonisolated func legacyDate(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var dbdt = DBDATETIME()
        _ = withUnsafeMutableBytes(of: &dbdt) { ptr in
            dbconvert(conn, type, data, len, 61, // SYBDATETIME
                      ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                      Int32(MemoryLayout<DBDATETIME>.size))
        }
        var rec = DBDATEREC()
        dbdatecrack(conn, &rec, &dbdt)
        var c = DateComponents()
        c.year = Int(rec.dateyear); c.month = Int(rec.datemonth) + 1; c.day = Int(rec.datedmonth)
        c.hour = Int(rec.datehour); c.minute = Int(rec.dateminute); c.second = Int(rec.datesecond)
        c.nanosecond = Int(rec.datemsecond) * 1_000_000
        return (Calendar(identifier: .gregorian).date(from: c) as Sendable?) ?? NSNull()
    }

    private nonisolated func msDateTime(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var buf = [CChar](repeating: 0, count: 65)
        let count = Int32(64) // Leave last byte as null
        let rc = buf.withUnsafeMutableBytes { ptr in
            dbconvert(conn, type, data, len, 47, // SYBCHAR
                      ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                      count)
        }
        guard rc != FAIL else { return NSNull() }
        let str = String(cString: buf).trimmingCharacters(in: .whitespaces)
        for fmt in SQLClient.isoFormatters { if let d = fmt.date(from: str) { return d as Sendable } }
        return str
    }

    private nonisolated func convertToDecimal(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var buf = [CChar](repeating: 0, count: 65)
        let count = Int32(64) // Leave last byte as null
        _ = buf.withUnsafeMutableBytes { ptr in
            dbconvert(conn, type, data, len, 47, // SYBCHAR
                      ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                      count)
        }
        return NSDecimalNumber(string: String(cString: buf).trimmingCharacters(in: .whitespaces))
    }

    private static let isoFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss.SSSSSSS", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "HH:mm:ss.SSSSSSS", "HH:mm:ss"].map {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = $0
            return df
        }
    }()

    private static func buildSQL(_ template: String, parameters: [Any?]) throws -> String {
        let parts = template.components(separatedBy: "?")
        guard parts.count - 1 == parameters.count else { throw SQLClientError.parameterCountMismatch }
        var result = ""
        for (i, param) in parameters.enumerated() {
            result += parts[i]
            result += sqlLiteral(for: param)
        }
        result += parts[parameters.count]
        return result
    }

    private static func sqlLiteral(for value: Any?) -> String {
        guard let value = value else { return "NULL" }
        switch value {
        case let s as String: return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
        case let n as NSNumber: return n.stringValue
        case let u as UUID: return "'" + u.uuidString + "'"
        case let d as Date:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return "'" + df.string(from: d) + "'"
        case is NSNull: return "NULL"
        default: return "'" + "\(value)".replacingOccurrences(of: "'", with: "''") + "'"
        }
    }

    private func runBlocking<T: Sendable>(_ body: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try body()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlockingVoid(_ body: @Sendable @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                body()
                continuation.resume()
            }
        }
    }
}

private func SQLClient_errorHandler(dbproc: OpaquePointer?, severity: Int32, dberr: Int32, oserr: Int32, dberrstr: UnsafeMutablePointer<CChar>?, oserrstr: UnsafeMutablePointer<CChar>?) -> Int32 {
    let msg = dberrstr.map { String(cString: $0) } ?? "Unknown FreeTDS error"
    if ProcessInfo.processInfo.environment["SQL_CLIENT_DEBUG"] != nil {
        print("DEBUG SQL Error: [\(dberr)] \(msg) (severity: \(severity))")
    }
    NotificationCenter.default.post(name: .SQLClientMessage, object: nil, userInfo: [SQLClientMessageKey.code: Int(dberr), SQLClientMessageKey.message: msg, SQLClientMessageKey.severity: Int(severity)])
    return 1 // INT_CANCEL
}

private func SQLClient_messageHandler(dbproc: OpaquePointer?, msgno: DBINT, msgstate: Int32, severity: Int32, msgtext: UnsafeMutablePointer<CChar>?, srvname: UnsafeMutablePointer<CChar>?, proc: UnsafeMutablePointer<CChar>?, line: Int32) -> Int32 {
    let msg = msgtext.map { String(cString: $0) } ?? ""
    if severity > 0 && ProcessInfo.processInfo.environment["SQL_CLIENT_DEBUG"] != nil {
        print("DEBUG SQL Message: [\(msgno)] \(msg) (severity: \(severity))")
    }
    NotificationCenter.default.post(name: .SQLClientMessage, object: nil, userInfo: [SQLClientMessageKey.code: Int(msgno), SQLClientMessageKey.message: msg, SQLClientMessageKey.severity: Int(severity)])
    return 0
}
