// SQLDataTable.swift
// Swift equivalent of SerializableDataTable for SQLClient-Swift.
//
// Provides a typed, named table with JSON-serializable cell values,
// Markdown rendering, and a DataSet (multi-table) container.

import Foundation

// MARK: - Column Type Enum

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
    case object(String)

    public var anyValue: Any? {
        switch self {
        case .null: return nil
        case .string(let v): return v
        case .int16(let v): return v
        case .int32(let v): return v
        case .int64(let v): return v
        case .uint16(let v): return v
        case .uint32(let v): return v
        case .uint64(let v): return v
        case .decimal(let v): return v
        case .double(let v): return v
        case .float(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .bytes(let v): return v
        case .uuid(let v): return v
        case .object(let v): return v
        }
    }

    public var displayString: String {
        switch self {
        case .null: return ""
        case .string(let v): return v.replacingOccurrences(of: "|", with: "\\|")
        case .int16(let v): return "\(v)"
        case .int32(let v): return "\(v)"
        case .int64(let v): return "\(v)"
        case .uint16(let v): return "\(v)"
        case .uint32(let v): return "\(v)"
        case .uint64(let v): return "\(v)"
        case .decimal(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .bool(let v): return v ? "true" : "false"
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .bytes(let v): return v.map { String(format: "%02x", $0) }.joined()
        case .uuid(let v): return v.uuidString
        case .object(let v): return v
        }
    }
}

// MARK: - SQLDataTable

public struct SQLDataTable: Codable, Sendable {
    public let name: String?
    public let columns: [SQLDataColumn]
    public let rows: [[SQLCellValue]]
    
    public init(name: String? = nil, columns: [SQLDataColumn], rows: [[SQLCellValue]]) {
        self.name = name
        self.columns = columns
        self.rows = rows
    }
    
    public var rowCount: Int { rows.count }
    public var columnCount: Int { columns.count }

    // MARK: Subscripts

    public subscript(row: Int, column: Int) -> SQLCellValue {
        guard row >= 0, row < rows.count, column >= 0, column < columns.count, column < rows[row].count else { return .null }
        return rows[row][column]
    }

    public subscript(row: Int, columnName: String) -> SQLCellValue {
        guard let colIndex = columns.firstIndex(where: { $0.name.caseInsensitiveCompare(columnName) == .orderedSame }) else {
            return .null
        }
        return self[row, colIndex]
    }
    
    // MARK: Row as Dictionary (columnName:Value)
    public func row(at index: Int) -> [String: SQLCellValue] {
        guard index >= 0 && index < rows.count else { return [:] }
        var dict: [String: SQLCellValue] = [:]
        for (ci, col) in columns.enumerated() where ci < rows[index].count {
            dict[col.name] = rows[index][ci]
        }
        return dict
    }

    // MARK: Column
    public func column(named name: String) -> [SQLCellValue] {
        guard let ci = columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return [] }
        return rows.map { $0.count > ci ? $0[ci] : .null }
    }

    // MARK: Markdown
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
        return try rows.map { rowCells in
            let storage: [(key: String, value: any Sendable)] = rowCells.enumerated().compactMap { (ci, cell) in
                guard ci < columns.count else { return nil }
                let value: any Sendable = cell.anyValue.map { $0 as AnyObject } ?? NSNull()
                return (key: columns[ci].name, value: value)
            }
            let row = SQLRow(storage)
            return try T(from: SQLRowDecoder(row: row))
        }
    }

    // MARK: SQLRow compatibility
    public func toSQLRows() -> [SQLRow] {
        rows.map { rowCells in
            let storage: [(key: String, value: any Sendable)] = rowCells.enumerated().compactMap { (ci, cell) in
                guard ci < columns.count else { return nil }
                let value: any Sendable = cell.anyValue.map { $0 as AnyObject } ?? NSNull()
                return (key: columns[ci].name, value: value)
            }
            return SQLRow(storage)
        }
    }
}

// MARK: - SQLDataSet

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