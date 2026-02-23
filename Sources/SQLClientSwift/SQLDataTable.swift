// SQLDataTable.swift
// Swift equivalent of SerializableDataTable for SQLClient-Swift.
// Provides a typed, named table with JSON-serializable cell values,
// Markdown rendering, and a DataSet (multi-table) container.

import Foundation

// MARK: - Column Type Enum

/// Type descriptor for a column — mirrors C# ColumnValueTypeEnum.
public enum SQLColumnType: String, Codable, Sendable {
    case string    = "String"
    case int16     = "Int16"
    case int32     = "Int32"
    case int64     = "Int64"
    case uint16    = "UInt16"
    case uint32    = "UInt32"
    case uint64    = "UInt64"
    case decimal   = "Decimal"
    case double    = "Double"
    case float     = "Float"
    case boolean   = "Boolean"
    case dateTime  = "DateTime"
    case byte      = "Byte"
    case byteArray = "ByteArray"
    case guid      = "Guid"
    case object    = "Object"
}

// MARK: - Column Descriptor

public struct SQLDataColumn: Codable, Sendable {
    public let name: String
    public let type: SQLColumnType

    public init(name: String, type: SQLColumnType) {
        self.name = name
        self.type = type
    }
}

// MARK: - Cell Value

/// A strongly-typed, Codable cell value preserving the original Swift type.
public enum SQLCellValue: Codable, Sendable, Equatable {
    case null
    case string(String)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case decimal(Decimal)
    case double(Double)
    case float(Float)
    case bool(Bool)
    case date(Date)
    case bytes(Data)
    case uuid(UUID)
    case object(String)   // JSON-encoded fallback

    /// Underlying value as Any? for compatibility with existing code.
    public var anyValue: Any? {
        switch self {
        case .null:           return nil
        case .string(let v):  return v
        case .int16(let v):   return v
        case .int32(let v):   return v
        case .int64(let v):   return v
        case .uint16(let v):  return v
        case .uint32(let v):  return v
        case .uint64(let v):  return v
        case .decimal(let v): return v
        case .double(let v):  return v
        case .float(let v):   return v
        case .bool(let v):    return v
        case .date(let v):    return v
        case .bytes(let v):   return v
        case .uuid(let v):    return v
        case .object(let v):  return v
        }
    }

    /// String for Markdown rendering.
    public var displayString: String {
        switch self {
        case .null:           return ""
        case .string(let v):  return v.replacingOccurrences(of: "|", with: "\\|")
        case .int16(let v):   return "\(v)"
        case .int32(let v):   return "\(v)"
        case .int64(let v):   return "\(v)"
        case .uint16(let v):  return "\(v)"
        case .uint32(let v):  return "\(v)"
        case .uint64(let v):  return "\(v)"
        case .decimal(let v): return "\(v)"
        case .double(let v):  return "\(v)"
        case .float(let v):   return "\(v)"
        case .bool(let v):    return v ? "true" : "false"
        case .date(let v):
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return df.string(from: v)
        case .bytes(let v):   return v.base64EncodedString()
        case .uuid(let v):    return v.uuidString
        case .object(let v):  return v
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case type, value }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:            try c.encode("null",    forKey: .type); try c.encodeNil(forKey: .value)
        case .string(let v):   try c.encode("string",  forKey: .type); try c.encode(v,  forKey: .value)
        case .int16(let v):    try c.encode("int16",   forKey: .type); try c.encode(v,  forKey: .value)
        case .int32(let v):    try c.encode("int32",   forKey: .type); try c.encode(v,  forKey: .value)
        case .int64(let v):    try c.encode("int64",   forKey: .type); try c.encode(v,  forKey: .value)
        case .uint16(let v):   try c.encode("uint16",  forKey: .type); try c.encode(v,  forKey: .value)
        case .uint32(let v):   try c.encode("uint32",  forKey: .type); try c.encode(v,  forKey: .value)
        case .uint64(let v):   try c.encode("uint64",  forKey: .type); try c.encode(v,  forKey: .value)
        case .decimal(let v):  try c.encode("decimal", forKey: .type); try c.encode(v,  forKey: .value)
        case .double(let v):   try c.encode("double",  forKey: .type); try c.encode(v,  forKey: .value)
        case .float(let v):    try c.encode("float",   forKey: .type); try c.encode(v,  forKey: .value)
        case .bool(let v):     try c.encode("bool",    forKey: .type); try c.encode(v,  forKey: .value)
        case .date(let v):     try c.encode("date",    forKey: .type); try c.encode(v.timeIntervalSince1970, forKey: .value)
        case .bytes(let v):    try c.encode("bytes",   forKey: .type); try c.encode(v.base64EncodedString(), forKey: .value)
        case .uuid(let v):     try c.encode("uuid",    forKey: .type); try c.encode(v.uuidString, forKey: .value)
        case .object(let v):   try c.encode("object",  forKey: .type); try c.encode(v,  forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        switch t {
        case "null":    self = .null
        case "string":  self = .string(try c.decode(String.self,  forKey: .value))
        case "int16":   self = .int16(try c.decode(Int16.self,    forKey: .value))
        case "int32":   self = .int32(try c.decode(Int32.self,    forKey: .value))
        case "int64":   self = .int64(try c.decode(Int64.self,    forKey: .value))
        case "uint16":  self = .uint16(try c.decode(UInt16.self,  forKey: .value))
        case "uint32":  self = .uint32(try c.decode(UInt32.self,  forKey: .value))
        case "uint64":  self = .uint64(try c.decode(UInt64.self,  forKey: .value))
        case "decimal": self = .decimal(try c.decode(Decimal.self, forKey: .value))
        case "double":  self = .double(try c.decode(Double.self,  forKey: .value))
        case "float":   self = .float(try c.decode(Float.self,    forKey: .value))
        case "bool":    self = .bool(try c.decode(Bool.self,      forKey: .value))
        case "date":    self = .date(Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .value)))
        case "bytes":   self = .bytes(Data(base64Encoded: try c.decode(String.self, forKey: .value)) ?? Data())
        case "uuid":    self = .uuid(UUID(uuidString: try c.decode(String.self, forKey: .value)) ?? UUID())
        default:        self = .object(try c.decode(String.self,  forKey: .value))
        }
    }

    // MARK: Build from raw FreeTDS value

    /// Converts a raw value from `columnValue()` into a typed `SQLCellValue`
    /// using the FreeTDS column type code.
    internal static func from(raw: Sendable, freeTDSType: Int32) -> SQLCellValue {
        if raw is NSNull { return .null }
        switch Int(freeTDSType) {
        case 48:                         // SYBINT1 → stored as UInt8 in NSNumber
            return (raw as? NSNumber).map { .int16(Int16($0.uint8Value)) } ?? .null
        case 52:                         // SYBINT2
            return (raw as? NSNumber).map { .int16($0.int16Value) } ?? .null
        case 56:                         // SYBINT4
            return (raw as? NSNumber).map { .int32($0.int32Value) } ?? .null
        case 127:                        // SYBINT8
            return (raw as? NSNumber).map { .int64($0.int64Value) } ?? .null
        case 59:                         // SYBREAL
            return (raw as? NSNumber).map { .float($0.floatValue) } ?? .null
        case 62:                         // SYBFLT8
            return (raw as? NSNumber).map { .double($0.doubleValue) } ?? .null
        case 50, 104:                    // SYBBIT / SYBBITN
            return (raw as? NSNumber).map { .bool($0.boolValue) } ?? .null
        case 55, 63, 60, 122, 110:       // decimal / numeric / money
            return (raw as? NSDecimalNumber).map { .decimal($0.decimalValue) } ?? .null
        case 36:                         // SYBUNIQUE
            return (raw as? UUID).map { .uuid($0) } ?? .null
        case 45, 37, 34, 173, 174, 167: // binary types
            return (raw as? Data).map { .bytes($0) } ?? .null
        case 61, 58, 111, 40, 41, 42, 43, 187, 188: // date/time types
            return (raw as? Date).map { .date($0) } ?? .null
        default:                         // char / varchar / text / xml / nvarchar etc.
            return (raw as? String).map { .string($0) } ?? .null
        }
    }

    /// Maps a FreeTDS type code to an SQLColumnType.
    internal static func columnType(for freeTDSType: Int32) -> SQLColumnType {
        switch Int(freeTDSType) {
        case 48:                         return .byte
        case 52:                         return .int16
        case 56:                         return .int32
        case 127:                        return .int64
        case 59:                         return .float
        case 62:                         return .double
        case 50, 104:                    return .boolean
        case 55, 63, 60, 122, 110:       return .decimal
        case 36:                         return .guid
        case 45, 37, 34, 173, 174, 167: return .byteArray
        case 61, 58, 111, 40, 41, 42, 43, 187, 188: return .dateTime
        default:                         return .string
        }
    }
}

// MARK: - SQLDataTable

/// A named, typed result table — Swift equivalent of SerializableDataTable.
public struct SQLDataTable: Codable, Sendable {

    /// Optional table name.
    public let name: String?

    /// Column descriptors in declaration order.
    public let columns: [SQLDataColumn]

    /// All rows as strongly-typed cell arrays.
    public let rows: [[SQLCellValue]]

    public var rowCount:    Int { rows.count }
    public var columnCount: Int { columns.count }

    internal init(name: String?, columns: [SQLDataColumn], rows: [[SQLCellValue]]) {
        self.name    = name
        self.columns = columns
        self.rows    = rows
    }

    // MARK: Access

    /// Cell at row index and column name (case-insensitive).
    public subscript(row: Int, column: String) -> SQLCellValue {
        guard row >= 0 && row < rows.count,
              let ci = columns.firstIndex(where: { $0.name.caseInsensitiveCompare(column) == .orderedSame })
        else { return .null }
        return rows[row][ci]
    }

    /// Cell at row and column index.
    public subscript(row: Int, column: Int) -> SQLCellValue {
        guard row >= 0 && row < rows.count,
              column >= 0 && column < columns.count
        else { return .null }
        return rows[row][column]
    }

    /// Row as a dictionary keyed by column name.
    public func row(at index: Int) -> [String: SQLCellValue] {
        guard index >= 0 && index < rows.count else { return [:] }
        var dict: [String: SQLCellValue] = [:]
        for (ci, col) in columns.enumerated() {
            dict[col.name] = rows[index][ci]
        }
        return dict
    }

    /// All values for a named column.
    public func column(named name: String) -> [SQLCellValue] {
        guard let ci = columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return [] }
        return rows.map { $0[ci] }
    }

    // MARK: Markdown

    /// Renders as a GitHub-flavoured Markdown table.
    public func toMarkdown() -> String {
        var lines: [String] = []
        if let name = name, !name.isEmpty { lines.append("# \(name)\n") }
        lines.append("| " + columns.map(\.name).joined(separator: " | ") + " |")
        lines.append("|" + columns.map { _ in "---|" }.joined())
        for row in rows {
            lines.append("| " + row.map(\.displayString).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Decodable rows

    /// Decodes each row into a `Decodable` type using column names as coding keys.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> [T] {
        try rows.map { rowCells in
            let storage: [(key: String, value: Sendable)] = rowCells.enumerated().compactMap { (ci, cell) in
                guard ci < columns.count else { return nil }
                let value: Sendable = cell.anyValue.map { $0 as AnyObject } ?? NSNull()
                return (key: columns[ci].name, value: value)
            }
            return try T(from: SQLRowDecoder(row: SQLRow(storage)))
        }
    }

    // MARK: SQLRow compatibility

    /// Converts to `[SQLRow]` for compatibility with existing query methods.
    public func toSQLRows() -> [SQLRow] {
        rows.map { rowCells in
            let storage: [(key: String, value: Sendable)] = rowCells.enumerated().compactMap { (ci, cell) in
                guard ci < columns.count else { return nil }
                let value: Sendable = cell.anyValue.map { $0 as AnyObject } ?? NSNull()
                return (key: columns[ci].name, value: value)
            }
            return SQLRow(storage)
        }
    }
}

// MARK: - SQLDataSet

/// A collection of SQLDataTables — equivalent to a .NET DataSet.
public struct SQLDataSet: Codable, Sendable {
    public let tables: [SQLDataTable]
    public var count: Int { tables.count }

    public subscript(index: Int) -> SQLDataTable? {
        guard index >= 0 && index < tables.count else { return nil }
        return tables[index]
    }

    public subscript(name: String) -> SQLDataTable? {
        tables.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
    }

    internal init(tables: [SQLDataTable]) { self.tables = tables }
}

// MARK: - SQLClientResult extension

extension SQLClientResult {
    /// Converts the first result table into an SQLDataTable.
    /// Call after `execute(_:)` when you need typed column info.
    public func asDataTable(name: String? = nil) -> SQLDataTable {
        asSQLDataSet().tables.first ?? SQLDataTable(name: name, columns: [], rows: [])
    }

    /// Converts all result tables into an SQLDataSet.
    public func asSQLDataSet() -> SQLDataSet {
        let dataTables = tables.enumerated().map { (idx, sqlRows) -> SQLDataTable in
            guard let first = sqlRows.first else {
                return SQLDataTable(name: "Table\(idx + 1)", columns: [], rows: [])
            }
            let cols = first.columns.map { name in
                // Infer type from first non-null value in the column
                let sample = sqlRows.compactMap({ $0[name] }).first(where: { !($0 is NSNull) })
                return SQLDataColumn(name: name, type: inferColumnType(from: sample))
            }
            let dataRows: [[SQLCellValue]] = sqlRows.map { sqlRow in
                cols.map { col in
                    guard let raw = sqlRow[col.name] else { return .null }
                    return cellValueFromAny(raw, columnType: col.type)
                }
            }
            return SQLDataTable(name: idx == 0 ? nil : "Table\(idx + 1)", columns: cols, rows: dataRows)
        }
        return SQLDataSet(tables: dataTables)
    }

    private func inferColumnType(from value: Any?) -> SQLColumnType {
        switch value {
        case is Bool:           return .boolean
        case is Float:          return .float
        case is Double:         return .double
        case is NSDecimalNumber: return .decimal
        case is Int16:          return .int16
        case is Int32:          return .int32
        case is Int64:          return .int64
        case is UInt16:         return .uint16
        case is UInt32:         return .uint32
        case is UInt64:         return .uint64
        case is Date:           return .dateTime
        case is Data:           return .byteArray
        case is UUID:           return .guid
        case let n as NSNumber:
            let t = String(cString: n.objCType)
            switch t {
            case "f":  return .float
            case "d":  return .double
            case "s":  return .int16
            case "i", "l": return .int32
            case "q":  return .int64
            case "S":  return .uint16
            case "I", "L": return .uint32
            case "Q":  return .uint64
            case "c", "C": return .boolean
            case "B":  return .byte
            default:   return .int32
            }
        default:                return .string
        }
    }

    private func cellValueFromAny(_ raw: Any, columnType: SQLColumnType) -> SQLCellValue {
        if raw is NSNull { return .null }
        switch columnType {
        case .string:    return (raw as? String).map { .string($0) } ?? .string("\(raw)")
        case .int16:     return (raw as? NSNumber).map { .int16($0.int16Value) } ?? .null
        case .int32:     return (raw as? NSNumber).map { .int32($0.int32Value) } ?? .null
        case .int64:     return (raw as? NSNumber).map { .int64($0.int64Value) } ?? .null
        case .uint16:    return (raw as? NSNumber).map { .uint16($0.uint16Value) } ?? .null
        case .uint32:    return (raw as? NSNumber).map { .uint32($0.uint32Value) } ?? .null
        case .uint64:    return (raw as? NSNumber).map { .uint64($0.uint64Value) } ?? .null
        case .float:     return (raw as? NSNumber).map { .float($0.floatValue) } ?? .null
        case .double:    return (raw as? NSNumber).map { .double($0.doubleValue) } ?? .null
        case .decimal:   return (raw as? NSDecimalNumber).map { .decimal($0.decimalValue) } ?? .null
        case .boolean:   return (raw as? NSNumber).map { .bool($0.boolValue) } ?? .null
        case .byte:      return (raw as? NSNumber).map { .int16(Int16($0.uint8Value)) } ?? .null
        case .byteArray: return (raw as? Data).map { .bytes($0) } ?? .null
        case .dateTime:  return (raw as? Date).map { .date($0) } ?? .null
        case .guid:      return (raw as? UUID).map { .uuid($0) } ?? .null
        case .object:    return .object("\(raw)")
        }
    }
}

// MARK: - SQLClient convenience methods

extension SQLClient {

    /// Executes SQL and returns a typed `SQLDataTable` directly.
    ///
    /// ```swift
    /// let table = try await client.dataTable("SELECT * FROM Users")
    /// print(table.toMarkdown())
    /// ```
    public func dataTable(_ sql: String, name: String? = nil) async throws -> SQLDataTable {
        let result = try await execute(sql)
        var dt = result.asDataTable(name: name)
        // Apply the provided name if given
        if let name = name {
            dt = SQLDataTable(name: name, columns: dt.columns, rows: dt.rows)
        }
        return dt
    }

    /// Executes SQL and returns all result tables as an `SQLDataSet`.
    ///
    /// ```swift
    /// let ds = try await client.dataSet("EXEC sp_GetReports")
    /// let firstTable = ds[0]
    /// ```
    public func dataSet(_ sql: String) async throws -> SQLDataSet {
        try await execute(sql).asSQLDataSet()
    }
}
