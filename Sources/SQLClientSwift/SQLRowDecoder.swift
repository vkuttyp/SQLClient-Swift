// SQLRowDecoder.swift
// Enables automatic Decodable mapping of SQLRow → any Swift struct/class.
//
// Usage:
//   struct User: Decodable { let id: Int; let name: String; let createdAt: Date }
//   let users: [User] = try await client.query("SELECT id, name, created_at FROM Users")
//
// Column name matching is case-insensitive ("created_at" matches CodingKey "createdAt"
// via the default snake_case strategy, or exact match first).

import Foundation

/// Internal decoder that bridges a `SQLRow` into Swift's `Decodable` protocol.
internal struct SQLRowDecoder: Decoder {
    let row: SQLRow
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(SQLRowKeyedContainer<Key>(row: row, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            .init(codingPath: codingPath, debugDescription: "SQLRow does not support unkeyed decoding."))
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(
            Any.self,
            .init(codingPath: codingPath, debugDescription: "SQLRow does not support single-value decoding."))
    }
}

// MARK: - Keyed Container

private struct SQLRowKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let row: SQLRow
    var codingPath: [CodingKey]

    var allKeys: [Key] { row.columns.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { resolvedValue(for: key) != nil }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = resolvedValue(for: key) else { return true }
        return value is NSNull
    }

    func decode(_ type: Bool.Type,   forKey key: Key) throws -> Bool   { try cast(key) }
    func decode(_ type: Int.Type,    forKey key: Key) throws -> Int    { try cast(key) }
    func decode(_ type: Int8.Type,   forKey key: Key) throws -> Int8   { try cast(key) }
    func decode(_ type: Int16.Type,  forKey key: Key) throws -> Int16  { try cast(key) }
    func decode(_ type: Int32.Type,  forKey key: Key) throws -> Int32  { try cast(key) }
    func decode(_ type: Int64.Type,  forKey key: Key) throws -> Int64  { try cast(key) }
    func decode(_ type: UInt.Type,   forKey key: Key) throws -> UInt   { try cast(key) }
    func decode(_ type: UInt8.Type,  forKey key: Key) throws -> UInt8  { try cast(key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try cast(key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try cast(key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try cast(key) }
    func decode(_ type: Float.Type,  forKey key: Key) throws -> Float  { try cast(key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try cast(key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try cast(key) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try requireValue(for: key)

        // Special-case common types before falling back to nested decoding.
        switch type {
        case is Date.Type:
            if let d = value as? Date { return d as! T }
            if let s = value as? String, let d = parseDate(s) { return d as! T }
        case is Data.Type:
            if let d = value as? Data { return d as! T }
        case is UUID.Type:
            if let u = value as? UUID { return u as! T }
        case is Decimal.Type:
            if let n = value as? NSDecimalNumber { return n.decimalValue as! T }
        case is URL.Type:
            if let s = value as? String, let u = URL(string: s) { return u as! T }
        default: break
        }

        // Nested Decodable (e.g. enums with RawRepresentable conformance via Codable).
        if let str = value as? String,
           let raw = str as? T { return raw }

        // Fall back to nested decoder.
        let subDecoder = SQLRowDecoder(row: row, codingPath: codingPath + [key])
        return try T(from: subDecoder)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        KeyedDecodingContainer(SQLRowKeyedContainer<NestedKey>(row: row, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self,
            .init(codingPath: codingPath, debugDescription: "Unkeyed containers not supported."))
    }

    func superDecoder() throws -> Decoder {
        SQLRowDecoder(row: row, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        SQLRowDecoder(row: row, codingPath: codingPath + [key])
    }

    // MARK: Helpers

    /// Resolves a CodingKey to a row value using:
    ///   1. Exact column name match
    ///   2. Case-insensitive match
    ///   3. snake_case ↔ camelCase conversion
    private func resolvedValue(for key: Key) -> Any? {
        let name = key.stringValue
        if let v = row[name] { return v }

        // Case-insensitive
        let lower = name.lowercased()
        for col in row.columns where col.lowercased() == lower {
            return row[col]
        }

        // snake_case → camelCase and vice versa
        let snake = toSnakeCase(name)
        for col in row.columns where col.lowercased() == snake {
            return row[col]
        }
        let camel = toCamelCase(name)
        for col in row.columns where col.lowercased() == camel.lowercased() {
            return row[col]
        }

        return nil
    }

    private func requireValue(for key: Key) throws -> Any {
        guard let value = resolvedValue(for: key) else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: codingPath,
                debugDescription: "Column '\(key.stringValue)' not found in result set. " +
                    "Available columns: \(row.columns.joined(separator: ", "))"))
        }
        return value
    }

    private func cast<T>(_ key: Key) throws -> T {
        // Validate key is in columns
        let value = try requireValue(for: key)

        // Direct cast as type 
        if let v = value as? T { return v }
        
        // If type is NSNumber supported
        if let n = value as? NSNumber {
            switch T.self {
            case is Bool.Type:   return (n.boolValue)   as! T
            case is Int.Type:    return (n.intValue)    as! T
            case is Int8.Type:   return (n.int8Value)   as! T
            case is Int16.Type:  return (n.int16Value)  as! T
            case is Int32.Type:  return (n.int32Value)  as! T
            case is Int64.Type:  return (n.int64Value)  as! T
            case is UInt.Type:   return UInt(n.uintValue)   as! T
            case is UInt8.Type:  return UInt8(n.uint8Value) as! T
            case is UInt16.Type: return UInt16(n.uint16Value) as! T
            case is UInt32.Type: return UInt32(n.uint32Value) as! T
            case is UInt64.Type: return UInt64(n.uint64Value) as! T
            case is Float.Type:  return (n.floatValue)  as! T
            case is Double.Type: return (n.doubleValue) as! T
            default: break
            }
        }
       // String → primitive conversions.
        if let s = value as? String {
            switch T.self {
            case is Int.Type:
                guard let i = Int(s) else {
                    throw DecodingError.typeMismatch(T.self, .init(
                        codingPath: codingPath + [key],
                        debugDescription: "Cannot convert '\(s)' to Int for column '\(key.stringValue)'."))
                }
                return i as! T

            case is Double.Type:
                guard let d = Double(s) else {
                    throw DecodingError.typeMismatch(T.self, .init(
                        codingPath: codingPath + [key],
                        debugDescription: "Cannot convert '\(s)' to Double for column '\(key.stringValue)'."))
                }
                return d as! T

            case is Bool.Type:
                switch s.lowercased() {
                case "true",  "1", "yes": return true  as! T
                case "false", "0", "no":  return false as! T
                default:
                    throw DecodingError.typeMismatch(T.self, .init(
                        codingPath: codingPath + [key],
                        debugDescription: "Cannot convert '\(s)' to Bool for column '\(key.stringValue)'. "
                            + "Expected one of: true, false, 1, 0, yes, no."))
                }

            default: break
            }
        }
        // No Conversion path succeeded
        throw DecodingError.typeMismatch(T.self, .init(
            codingPath: codingPath + [key],
            debugDescription: "Expected \(T.self), got \(type(of: value)) for column '\(key.stringValue)'"))
    }

    private func toSnakeCase(_ s: String) -> String {
        var result = ""
        for (i, ch) in s.enumerated() {
            if ch.isUppercase && i > 0 { result += "_" }
            result += ch.lowercased()
        }
        return result
    }

    private func toCamelCase(_ s: String) -> String {
        let parts = s.split(separator: "_")
        guard let first = parts.first else { return s }
        return first.lowercased() + parts.dropFirst().map { $0.capitalized }.joined()
    }

    private func parseDate(_ s: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
