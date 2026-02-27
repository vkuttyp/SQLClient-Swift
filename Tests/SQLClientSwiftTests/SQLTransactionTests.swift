import XCTest
@testable import SQLClientSwift

final class SQLTransactionTests: XCTestCase {
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
        
        try await client.run("IF OBJECT_ID('tempdb..#TranTest') IS NOT NULL DROP TABLE #TranTest;")
        try await client.run("CREATE TABLE #TranTest (Id INT, Name NVARCHAR(50));")
    }

    override func tearDown() async throws {
        if let c = client {
            await c.disconnect()
        }
    }

    func testCommitTransaction() async throws {
        try await client.beginTransaction()
        try await client.run("INSERT INTO #TranTest VALUES (1, 'Committed')")
        try await client.commitTransaction()

        let rows = try await client.query("SELECT Name FROM #TranTest WHERE Id = 1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].string("Name"), "Committed")
    }

    func testRollbackTransaction() async throws {
        try await client.beginTransaction()
        try await client.run("INSERT INTO #TranTest VALUES (2, 'RolledBack')")
        try await client.rollbackTransaction()

        let rows = try await client.query("SELECT Name FROM #TranTest WHERE Id = 2")
        XCTAssertEqual(rows.count, 0)
    }
}
