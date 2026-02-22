// SQLClientSwiftTests.swift
// Integration tests — require a live SQL Server.
// Set environment variables: HOST, USERNAME, PASSWORD, DATABASE (optional)

import XCTest
@testable import SQLClientSwift

final class SQLClientSwiftTests: XCTestCase {

    private func env(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? "" }
    private var host:     String { env("HOST") }
    private var username: String { env("USERNAME") }
    private var password: String { env("PASSWORD") }
    private var database: String { env("DATABASE") }
    private var canConnect: Bool { !host.isEmpty && !username.isEmpty && !password.isEmpty }
    private var client: SQLClient!       // global client

    private func makeClient() async throws -> SQLClient {
        let c = SQLClient()
        try await c.connect(server: host, username: username, password: password,
                                 database: database.isEmpty ? nil : database)
        return c
    }
    
    /// Called before each XCTest method is run. Able to throw errors on setup.
    /// Centralises boilerplate setup making 
    override func setupWithError() throws {
        try await super.setupWithError()
        guard canConnect else {
            throw XCTSkip("Set HOST, USERNAME, PASSWORD environment variables to run tests.")
        }
        client = try await makeClient()
    }

    /// Called after each XCTest method is run. Able to throw errors on cleanup.
    /// Ensures cleanup from each test is completed after the test is run. Before
    /// the next test is run.
    override func tearDownWithError() throws {
        try await client.disconnect()
        try await super.tearDownWithError()
    }


    func testConnect() async throws {
        // Use a local client, as the global client is already connected
        let localClient = SQLClient()
        try await localClient.connect(server: host, username: username, password: password,
                                 database: database.isEmpty ? nil : database)

        let connected = await localClient.isConnected
        XCTAssertTrue(connected)

        await localClient.disconnect()
        let isConnected = await localClient.isConnected
        XCTAssertFalse(isConnected)
    }

    func testDoubleConnectThrows() async throws {
        // Use a local client as the global client is already connected
        let localClient = SQLClient()
        try await localClient.connect(server: host, username: username, password: password,
                                 database: database.isEmpty ? nil : database)
        // Defer is used here as race condition on cleanup is inconsequential
        defer { Task { await localClient.disconnect() } }
        
        do {
            try await localClient.connect(server: host, username: username, password: password)
            XCTFail("Expected alreadyConnected")
        } catch SQLClientError.alreadyConnected { }
    }

    func testSelectScalar() async throws {
        let rows = try await client.query("SELECT 42 AS Answer")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].int("Answer"), 42)
    }

    func testSelectNull() async throws {
        let rows = try await client.query("SELECT NULL AS Val")
        XCTAssertTrue(rows[0].isNull("Val"))
    }

    func testSelectString() async throws {
        let rows = try await client.query("SELECT 'Hello' AS Msg")
        XCTAssertEqual(rows[0].string("Msg"), "Hello")
    }

    func testSelectFloat() async throws {
        let rows = try await client.query("SELECT CAST(3.14 AS FLOAT) AS Pi")
        XCTAssertEqual(rows[0].double("Pi") ?? 0, 3.14, accuracy: 0.001)
    }

    func testSelectBit() async throws {
        let rows = try await client.query("SELECT CAST(1 AS BIT) AS Flag")
        XCTAssertEqual(rows[0].bool("Flag"), true)
    }

    func testSelectDateTime() async throws {
        let rows = try await client.query("SELECT GETDATE() AS Now")
        XCTAssertNotNil(rows[0].date("Now"))
    }

    func testMultipleRows() async throws {
        let rows = try await client.query("SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0.int("n") }, [1, 2, 3])
    }

    func testMultipleResultSets() async throws {
        let result = try await client.execute("SELECT 1 AS A; SELECT 2 AS B;")
        XCTAssertEqual(result.tables.count, 2)
        XCTAssertEqual(result.tables[0][0].int("A"), 1)
        XCTAssertEqual(result.tables[1][0].int("B"), 2)
    }

    func testRowsAffected() async throws {
        try await client.run("""
            IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
            CREATE TABLE #T (id INT);
            INSERT INTO #T VALUES (1),(2),(3);
        """)
        let affected = try await client.run("UPDATE #T SET id = id + 10")
        XCTAssertEqual(affected, 3)
        try await client.run("DROP TABLE #T")
    }

    func testParameterisedQuery() async throws {
        let rows = try await client.execute("SELECT ? AS Name", parameters: ["O'Brien"])
        XCTAssertEqual(rows.rows[0].string("Name"), "O'Brien")
    }

    func testNullParameter() async throws {
        let rows = try await client.execute("SELECT ? AS Val", parameters: [nil])
        XCTAssertTrue(rows.rows[0].isNull("Val"))
    }

    func testParameterCountMismatch() async throws {
        defer { Task { await client.disconnect() } }
        do {
            _ = try await client.execute("SELECT ? AS A", parameters: [1, 2])
            XCTFail("Expected parameterCountMismatch")
        } catch SQLClientError.parameterCountMismatch { }
    }

    func testDecodableStruct() async throws {
        struct Point: Decodable { let x: Int; let y: Int }
        let points: [Point] = try await client.query("SELECT 10 AS x, 20 AS y")
        XCTAssertEqual(points[0].x, 10)
        XCTAssertEqual(points[0].y, 20)
    }

    func testDecodableSnakeCase() async throws {
        struct Item: Decodable { let itemId: Int; let itemName: String }
        let items: [Item] = try await client.query("SELECT 7 AS item_id, 'Widget' AS item_name")
        XCTAssertEqual(items[0].itemId,   7)
        XCTAssertEqual(items[0].itemName, "Widget")
    }

    func testBadSQLThrows() async throws {
        do {
            _ = try await client.execute("THIS IS NOT VALID SQL")
            XCTFail("Expected executionFailed")
        } catch SQLClientError.executionFailed { }
    }

    func testEmptySQLThrows() async throws {
        do {
            _ = try await client.execute("   ")
            XCTFail("Expected noCommandText")
        } catch SQLClientError.noCommandText { }
    }

    func testQueryBeforeConnectThrows() async throws {
        let client = SQLClient()
        do {
            _ = try await client.query("SELECT 1")
            XCTFail("Expected notConnected")
        } catch SQLClientError.notConnected { }
    }
}
