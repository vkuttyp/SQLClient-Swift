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

    private func makeClient() async throws -> SQLClient {
        guard canConnect else {
            throw XCTSkip("Set HOST, USERNAME, PASSWORD environment variables to run tests.")
        }
        let client = SQLClient()
        try await client.connect(server: host, username: username, password: password,
                                 database: database.isEmpty ? nil : database)
        return client
    }

    func testConnect() async throws {
        let client = try await makeClient()
        let connected = await client.isConnected
        XCTAssertTrue(connected)
        await client.disconnect()
        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }

    func testDoubleConnectThrows() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        do {
            try await client.connect(server: host, username: username, password: password)
            XCTFail("Expected alreadyConnected")
        } catch SQLClientError.alreadyConnected { }
    }

    func testSelectScalar() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT 42 AS Answer")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].int("Answer"), 42)
    }

    func testSelectNull() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT NULL AS Val")
        XCTAssertTrue(rows[0].isNull("Val"))
    }

    func testSelectString() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT 'Hello' AS Msg")
        XCTAssertEqual(rows[0].string("Msg"), "Hello")
    }

    func testSelectFloat() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT CAST(3.14 AS FLOAT) AS Pi")
        XCTAssertEqual(rows[0].double("Pi") ?? 0, 3.14, accuracy: 0.001)
    }

    func testSelectBit() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT CAST(1 AS BIT) AS Flag")
        XCTAssertEqual(rows[0].bool("Flag"), true)
    }

    func testSelectDateTime() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT GETDATE() AS Now")
        XCTAssertNotNil(rows[0].date("Now"))
    }

    func testMultipleRows() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.query("SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0.int("n") }, [1, 2, 3])
    }

    func testMultipleResultSets() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let result = try await client.execute("SELECT 1 AS A; SELECT 2 AS B;")
        XCTAssertEqual(result.tables.count, 2)
        XCTAssertEqual(result.tables[0][0].int("A"), 1)
        XCTAssertEqual(result.tables[1][0].int("B"), 2)
    }

    func testRowsAffected() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
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
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.execute("SELECT ? AS Name", parameters: ["O'Brien"])
        XCTAssertEqual(rows.rows[0].string("Name"), "O'Brien")
    }

    func testNullParameter() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        let rows = try await client.execute("SELECT ? AS Val", parameters: [nil])
        XCTAssertTrue(rows.rows[0].isNull("Val"))
    }

    func testParameterCountMismatch() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        do {
            _ = try await client.execute("SELECT ? AS A", parameters: [1, 2])
            XCTFail("Expected parameterCountMismatch")
        } catch SQLClientError.parameterCountMismatch { }
    }

    func testDecodableStruct() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        struct Point: Decodable { let x: Int; let y: Int }
        let points: [Point] = try await client.query("SELECT 10 AS x, 20 AS y")
        XCTAssertEqual(points[0].x, 10)
        XCTAssertEqual(points[0].y, 20)
    }

    func testDecodableSnakeCase() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        struct Item: Decodable { let itemId: Int; let itemName: String }
        let items: [Item] = try await client.query("SELECT 7 AS item_id, 'Widget' AS item_name")
        XCTAssertEqual(items[0].itemId,   7)
        XCTAssertEqual(items[0].itemName, "Widget")
    }

    func testBadSQLThrows() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
        do {
            _ = try await client.execute("THIS IS NOT VALID SQL")
            XCTFail("Expected executionFailed")
        } catch SQLClientError.executionFailed { }
    }

    func testEmptySQLThrows() async throws {
        let client = try await makeClient()
        defer { Task { await client.disconnect() } }
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
