import XCTest
@testable import SQLClientSwift

final class SQLBCPTests: XCTestCase {
    private func env(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? "" }
    private var host: String { env("HOST") }
    private var username: String { env("USERNAME") }
    private var password: String { env("PASSWORD") }
    private var database: String { env("DATABASE") }
    private var canConnect: Bool { !host.isEmpty && !username.isEmpty && !password.isEmpty }
    private var client: SQLClient!

    override func setUp() async throws {
        guard canConnect else { throw XCTSkip("No connection info") }
        client = SQLClient()
        try await client.connect(server: host, username: username, password: password, database: database.isEmpty ? nil : database)
        
        try await client.run("IF OBJECT_ID('BCPTest') IS NOT NULL DROP TABLE BCPTest;")
        try await client.run("CREATE TABLE BCPTest (Id INT, Name VARCHAR(50), Value FLOAT);")
    }

    override func tearDown() async throws {
        if let c = client {
            try? await c.run("IF OBJECT_ID('BCPTest') IS NOT NULL DROP TABLE BCPTest;")
            await c.disconnect()
        }
    }

    func testBulkInsert() async throws {
        var rows: [SQLRow] = []
        for i in 1...100 {
            let storage: [(key: String, value: Sendable)] = [
                (key: "Id", value: i),
                (key: "Name", value: "Row \(i)"),
                (key: "Value", value: Double(i) * 1.1)
            ]
            rows.append(SQLRow(storage, columnTypes: ["Id": 56, "Name": 39, "Value": 62]))
        }

        let inserted = try await client.bulkInsert(table: "BCPTest", rows: rows)
        XCTAssertEqual(inserted, 100)

        let countRows = try await client.query("SELECT COUNT(*) as cnt FROM BCPTest")
        XCTAssertEqual(countRows[0].int("cnt"), 100)
        
        let firstRow = try await client.query("SELECT Name FROM BCPTest WHERE Id = 42")
        XCTAssertEqual(firstRow[0].string("Name"), "Row 42")
    }
}
