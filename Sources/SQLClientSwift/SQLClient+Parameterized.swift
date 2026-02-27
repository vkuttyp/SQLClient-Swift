#if FREETDS_FOUND
import CFreeTDS
import Foundation

extension SQLClient {
    /// Executes a parameterized query using sp_executesql.
    /// This is safer and more efficient than string-building for complex queries.
    public func executeParameterized(_ sql: String, parameters: [SQLParameter]) async throws -> SQLClientResult {
        // sp_executesql @stmt, @params, @param1, @param2...
        
        // 1. Build the parameter definition string: "@p1 int, @p2 nvarchar(50)..."
        var defParts: [String] = []
        var rpcParams: [SQLParameter] = []
        
        // First parameter is the statement itself
        rpcParams.append(SQLParameter(name: "@stmt", value: sql, isOutput: false))
        
        for (i, p) in parameters.enumerated() {
            let pName = p.name ?? "@p\(i+1)"
            let typeStr = sqlTypeName(for: p.value)
            defParts.append("\(pName) \(typeStr)" + (p.isOutput ? " OUTPUT" : ""))
        }
        
        let paramDef = defParts.joined(separator: ", ")
        rpcParams.append(SQLParameter(name: "@params", value: paramDef, isOutput: false))
        
        // Add the actual values
        for (i, p) in parameters.enumerated() {
            let pName = p.name ?? "@p\(i+1)"
            rpcParams.append(SQLParameter(name: pName, value: p.value, isOutput: p.isOutput))
        }
        
        return try await executeRPC("sp_executesql", parameters: rpcParams)
    }

    private func sqlTypeName(for value: Sendable?) -> String {
        guard let value = value else { return "NVARCHAR(MAX)" }
        switch value {
        case is Int, is Int32: return "INT"
        case is Int16: return "SMALLINT"
        case is Int64: return "BIGINT"
        case is Float: return "REAL"
        case is Double: return "FLOAT"
        case is Bool: return "BIT"
        case is Data: return "VARBINARY(MAX)"
        case is Date: return "DATETIME"
        case is UUID: return "UNIQUEIDENTIFIER"
        default: return "NVARCHAR(MAX)"
        }
    }
}
#endif
