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
    
    internal init(_ dict: [(key: String, value: Sendable)]) {
        self.storage = dict
    }
    
    public var columns: [String] { storage.map(\.key) }
    
    public subscript(column: String) -> Any? {
        storage.first(where: { $0.key == column })?.value
    }
    
    public subscript(index: Int) -> Any? {
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
        Dictionary(uniqueKeysWithValues: storage)
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
    public init() {}

    public var maxTextSize: Int = 4096
    private var login:      OpaquePointer?
    private var connection: OpaquePointer?
    private var connected   = false

    public func connect(server: String, username: String, password: String, database: String? = nil) async throws {
        try await connect(options: SQLClientConnectionOptions(server: server, username: username, password: password, database: database))
    }

    public func connect(options: SQLClientConnectionOptions) async throws {
        guard !connected else { throw SQLClientError.alreadyConnected }
        
        let result = try await runBlocking {
            return try self._connectSync(options: options)
        }
        
        self.login = result.login.pointer
        self.connection = result.connection.pointer
        self.connected = true
    }

    public func disconnect() async {
        guard connected else { return }
        let lgn = self.login.map { TDSHandle(pointer: $0) }
        let conn = self.connection.map { TDSHandle(pointer: $0) }
        await runBlockingVoid {
            self._disconnectSync(login: lgn, connection: conn)
        }
        self.login = nil
        self.connection = nil
        self.connected = false
    }

    public func execute(_ sql: String) async throws -> SQLClientResult {
        guard connected, let conn = connection else { throw SQLClientError.notConnected }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SQLClientError.noCommandText }
        let maxText = self.maxTextSize
        let handle = TDSHandle(pointer: conn)
        
        return try await runBlocking {
            return try self._executeSync(sql: sql, connection: handle, maxTextSize: maxText)
        }
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

    private nonisolated func checkReachability(server: String, port: UInt16) throws {
        let host = CFHostCreateWithName(nil, server as CFString).takeRetainedValue()
        var error = CFStreamError()
        CFHostStartInfoResolution(host, .addresses, &error)
        
        guard error.error == 0 else {
            throw SQLClientError.connectionFailed(server: server)
        }

        // Attempt a TCP connection with a 5 second timeout
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, server as CFString, UInt32(port), &readStream, &writeStream)

        guard let read  = readStream?.takeRetainedValue(),
            let write = writeStream?.takeRetainedValue() else {
            throw SQLClientError.connectionFailed(server: server)
        }

        CFReadStreamOpen(read)
        CFWriteStreamOpen(write)

        let deadline = Date().addingTimeInterval(5)
        var connected = false

        while Date() < deadline {
            let readStatus  = CFReadStreamGetStatus(read)
            let writeStatus = CFWriteStreamGetStatus(write)
            if readStatus == .open && writeStatus == .open {
                connected = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        CFReadStreamClose(read)
        CFWriteStreamClose(write)

        guard connected else {
            throw SQLClientError.connectionFailed(server: server)
        }
    }

    private nonisolated func _connectSync(options: SQLClientConnectionOptions) throws -> (login: TDSHandle, connection: TDSHandle) {
        // Pre-flight — fail fast if the server isn't reachable at the TCP level.
        // Default port for SQL Server is 1433.
        try checkReachability(server: options.server, port: options.port ?? 1433)
        
        dbinit()
        dberrhandle(SQLClient_errorHandler)
        dbmsghandle(SQLClient_messageHandler)

        guard let lgn = dblogin() else { throw SQLClientError.loginAllocationFailed }

        dbsetlname(lgn, options.username, 2) // DBSETUSER
        dbsetlname(lgn, options.password, 3) // DBSETPWD
        dbsetlname(lgn, "SQLClientSwift", 5) // DBSETAPP

        if let port = options.port { dbsetlshort(lgn, Int32(port), 13) } // DBSETPORT
        if options.encryption != .request { dbsetlname(lgn, options.encryption.rawValue, 17) } // DBSETENCRYPTION
        dbsetlbool(lgn, options.useNTLMv2 ? 1 : 0, 16) // DBSETNTLMV2
        if options.networkAuth { dbsetlbool(lgn, 1, 15) } // DBSETNETWORKAUTH
        if options.readOnly { dbsetlbool(lgn, 1, 14) } // DBSETREADONLY
        if options.useUTF16 { dbsetlbool(lgn, 1, 18) } // DBSETUTF16
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
        dbexit()
    }

    private nonisolated func _executeSync(sql: String, connection: TDSHandle, maxTextSize: Int) throws -> SQLClientResult {
        let conn = connection.pointer
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
                for i in 1...numCols {
                    colMeta.append((name: String(cString: dbcolname(conn, Int32(i))), type: dbcoltype(conn, Int32(i))))
                }
                while dbnextrow(conn) != NO_MORE_ROWS {
                    var storage: [(key: String, value: Sendable)] = []
                    for (idx, col) in colMeta.enumerated() {
                        let colIdx = Int32(idx + 1)
                        storage.append((key: col.name, value: columnValue(conn: conn, column: colIdx, type: col.type)))
                    }
                    table.append(SQLRow(storage))
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
            return NSNumber(value: data.load(as: Int16.self))
        case 56: // SYBINT4
            return NSNumber(value: data.load(as: Int32.self))
        case 127: // SYBINT8
            return NSNumber(value: data.load(as: Int64.self))
        case 59: // SYBREAL
            return NSNumber(value: data.load(as: Float.self))
        case 62: // SYBFLT8
            return NSNumber(value: data.load(as: Double.self))
        case 50, 104: // SYBBIT, SYBBITN
            return NSNumber(value: data.load(as: UInt8.self) != 0)
        case 47, 39, 102, 103, 35, 99, 241: // SYBCHAR, SYBVARCHAR, SYBNCHAR, SYBNVARCHAR, SYBTEXT, SYBNTEXT, SYBXML
            let buf = UnsafeBufferPointer<UInt8>(start: data.assumingMemoryBound(to: UInt8.self), count: Int(len))
            return String(bytes: buf, encoding: .utf8) ?? String(bytes: buf, encoding: .windowsCP1252) ?? ""
        case 45, 37, 34, 173, 174, 167: // SYBBINARY, SYBVARBINARY, SYBIMAGE, SYBBIGBINARY, SYBBIGVARBINARY, SYBBLOB
            return Data(bytes: dataPtr, count: Int(len))
        case 61, 58, 111: // SYBDATETIME, SYBDATETIME4, SYBDATETIMN
            return legacyDate(conn: conn, type: type, data: data, len: len)
        case 40, 41, 42, 43, 187, 188: // SYBMSDATE, SYBMSTIME, SYBMSDATETIME2, SYBMSDATETIMEOFFSET, SYBBIGDATETIME, SYBBIGTIME
            return msDateTime(conn: conn, type: type, data: data, len: len)
        case 55, 63, 60, 122, 110: // SYBDECIMAL, SYBNUMERIC, SYBMONEY, SYBMONEY4, SYBMONEYN
            return convertToDecimal(conn: conn, type: type, data: data, len: len)
        case 36: // SYBUNIQUE
            guard len == 16 else { return NSNull() }
            var bytes = [UInt8](repeating: 0, count: 16)
            memcpy(&bytes, dataPtr, 16)
            return NSUUID(uuidBytes: &bytes) as UUID
        case 31: // SYBVOID
            return NSNull()
        default:
            return Data(bytes: dataPtr, count: Int(len))
        }
    }

    private nonisolated func legacyDate(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var dbdt = DBDATETIME()
        _ = dbconvert(conn, type, data, len, 61, // SYBDATETIME
                  UnsafeMutableRawPointer(&dbdt).assumingMemoryBound(to: UInt8.self),
                  Int32(MemoryLayout<DBDATETIME>.size))
        var rec = DBDATEREC()
        dbdatecrack(conn, &rec, &dbdt)
        var c = DateComponents()
        c.year = Int(rec.dateyear); c.month = Int(rec.datemonth) + 1; c.day = Int(rec.datedmonth)
        c.hour = Int(rec.datehour); c.minute = Int(rec.dateminute); c.second = Int(rec.datesecond)
        c.nanosecond = Int(rec.datemsecond) * 1_000_000
        return (Calendar(identifier: .gregorian).date(from: c) as Sendable?) ?? NSNull()
    }

    private nonisolated func msDateTime(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var buf = [CChar](repeating: 0, count: 64)
        let rc = dbconvert(conn, type, data, len, 47, // SYBCHAR
                           UnsafeMutableRawPointer(&buf).assumingMemoryBound(to: UInt8.self),
                           Int32(buf.count))
        guard rc != FAIL else { return NSNull() }
        let str = String(cString: buf).trimmingCharacters(in: .whitespaces)
        for fmt in SQLClient.isoFormatters { if let d = fmt.date(from: str) { return d as Sendable } }
        return str
    }

    private nonisolated func convertToDecimal(conn: OpaquePointer, type: Int32, data: UnsafeRawPointer, len: Int32) -> Sendable {
        var buf = [CChar](repeating: 0, count: 64)
        _ = dbconvert(conn, type, data, len, 47, // SYBCHAR
                  UnsafeMutableRawPointer(&buf).assumingMemoryBound(to: UInt8.self),
                  Int32(buf.count))
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
            Thread.detachNewThread {
                do { continuation.resume(returning: try body()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func runBlockingVoid(_ body: @Sendable @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                body()
                continuation.resume()
            }
        }
    }
}

private func SQLClient_errorHandler(dbproc: OpaquePointer?, severity: Int32, dberr: Int32, oserr: Int32, dberrstr: UnsafeMutablePointer<CChar>?, oserrstr: UnsafeMutablePointer<CChar>?) -> Int32 {
    let msg = dberrstr.map { String(cString: $0) } ?? "Unknown FreeTDS error"
    NotificationCenter.default.post(name: .SQLClientMessage, object: nil, userInfo: [SQLClientMessageKey.code: Int(dberr), SQLClientMessageKey.message: msg, SQLClientMessageKey.severity: Int(severity)])
    return 1 // INT_CANCEL
}

private func SQLClient_messageHandler(dbproc: OpaquePointer?, msgno: DBINT, msgstate: Int32, severity: Int32, msgtext: UnsafeMutablePointer<CChar>?, srvname: UnsafeMutablePointer<CChar>?, proc: UnsafeMutablePointer<CChar>?, line: Int32) -> Int32 {
    let msg = msgtext.map { String(cString: $0) } ?? ""
    NotificationCenter.default.post(name: .SQLClientMessage, object: nil, userInfo: [SQLClientMessageKey.code: Int(msgno), SQLClientMessageKey.message: msg, SQLClientMessageKey.severity: Int(severity)])
    return 0
}
