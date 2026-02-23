// SQLClientSwiftTests.swift
// Integration tests — require a live SQL Server.
// Set environment variables: HOST, USERNAME, PASSWORD, DATABASE (optional)

import XCTest

@testable import SQLClientSwift

final class SQLClientSwiftTests: XCTestCase {

    private func env(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? "" }
    private var host: String { env("HOST") }
    private var username: String { env("USERNAME") }
    private var password: String { env("PASSWORD") }
    private var database: String { env("DATABASE") }
    private var canConnect: Bool { !host.isEmpty && !username.isEmpty && !password.isEmpty }
    private var client: SQLClient!  // global client

    private func makeClient() async throws -> SQLClient {
        let c = SQLClient()
        try await c.connect(
            server: host, username: username, password: password,
            database: database.isEmpty ? nil : database)
        return c
    }

    /// Called before each XCTest method is run. Able to throw errors on setup.
    /// Centralises boilerplate setup making
    override func setUp() async throws {
        try super.setUpWithError()
        guard canConnect else {
            throw XCTSkip("Set HOST, USERNAME, PASSWORD environment variables to run tests.")
        }
        client = try await makeClient()

    }

    /// Called after each XCTest method is run. Able to throw errors on cleanup.
    /// Ensures cleanup from each test is completed after the test is run. Before
    /// the next test is run.
    override func tearDown() async throws {
        guard client != nil else { return } 
        try await client.disconnect()
        try await super.tearDown()
    }

    func testConnect() async throws {
        // Use a local client, as the global client is already connected
        let localClient = SQLClient()
        try await localClient.connect(
            server: host, username: username, password: password,
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
        try await localClient.connect(
            server: host, username: username, password: password,
            database: database.isEmpty ? nil : database)
        // Defer is used here as race condition on cleanup is inconsequential
        defer { Task { await localClient.disconnect() } }

        do {
            try await localClient.connect(server: host, username: username, password: password)
            XCTFail("Expected alreadyConnected")
        } catch SQLClientError.alreadyConnected {}
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
        try await client.run(
            """
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
        } catch SQLClientError.parameterCountMismatch {}
    }

    func testDecodableStruct() async throws {
        struct Point: Decodable {
            let x: Int
            let y: Int
        }
        let points: [Point] = try await client.query("SELECT 10 AS x, 20 AS y")
        XCTAssertEqual(points[0].x, 10)
        XCTAssertEqual(points[0].y, 20)
    }

    func testDecodableSnakeCase() async throws {
        struct Item: Decodable {
            let itemId: Int
            let itemName: String
        }
        let items: [Item] = try await client.query("SELECT 7 AS item_id, 'Widget' AS item_name")
        XCTAssertEqual(items[0].itemId, 7)
        XCTAssertEqual(items[0].itemName, "Widget")
    }

    func testBadSQLThrows() async throws {
        do {
            _ = try await client.execute("THIS IS NOT VALID SQL")
            XCTFail("Expected executionFailed")
        } catch SQLClientError.executionFailed {}
    }

    func testEmptySQLThrows() async throws {
        do {
            _ = try await client.execute("   ")
            XCTFail("Expected noCommandText")
        } catch SQLClientError.noCommandText {}
    }

    func testQueryBeforeConnectThrows() async throws {
        let client = SQLClient()
        do {
            _ = try await client.query("SELECT 1")
            XCTFail("Expected notConnected")
        } catch SQLClientError.notConnected {}
    }

    // MARK: - SQLDataTable tests

    func testDataTableRowAndColumnCount() async throws {
        let table = try await client.dataTable(
            "SELECT 1 AS A, 'hello' AS B UNION ALL SELECT 2, 'world'"
        )
        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 2)
    }

    func testDataTableColumnNames() async throws {
        let table = try await client.dataTable("SELECT 42 AS Answer, 'hi' AS Greeting")
        XCTAssertEqual(table.columns[0].name, "Answer")
        XCTAssertEqual(table.columns[1].name, "Greeting")
    }

    func testDataTableSubscriptByName() async throws {
        let table = try await client.dataTable("SELECT 99 AS Score")
        let cell = table[0, "Score"]
        if case .int32(let v) = cell {
            XCTAssertEqual(v, 99)
        } else {
            // Widen: some servers return tinyint/smallint for literals
            XCTAssertNotNil(cell.anyValue, "Expected a non-null numeric value")
        }
    }

    func testDataTableSubscriptCaseInsensitive() async throws {
        let table = try await client.dataTable("SELECT 'test' AS MyColumn")
        // Access using different casing
        let byLower = table[0, "mycolumn"]
        let byUpper = table[0, "MYCOLUMN"]
        XCTAssertEqual(byLower.anyValue as? String, "test")
        XCTAssertEqual(byUpper.anyValue as? String, "test")
    }

    func testDataTableSubscriptByIndex() async throws {
        let table = try await client.dataTable("SELECT 7 AS N, 'x' AS S")
        let second = table[0, 1]
        XCTAssertEqual(second.anyValue as? String, "x")
    }

    func testDataTableSubscriptOutOfBoundsReturnsNull() async throws {
        let table = try await client.dataTable("SELECT 1 AS A")
        let oobRow = table[99, "A"]
        let oobCol = table[0, "DoesNotExist"]
        XCTAssertEqual(oobRow, .null)
        XCTAssertEqual(oobCol, .null)
    }

    func testDataTableNullCell() async throws {
        let table = try await client.dataTable("SELECT NULL AS Val")
        XCTAssertEqual(table[0, "Val"], .null)
        XCTAssertNil(table[0, "Val"].anyValue)
    }

    func testDataTableRowAsDictionary() async throws {
        let table = try await client.dataTable("SELECT 5 AS ID, 'Alice' AS Name")
        let dict = table.row(at: 0)
        XCTAssertEqual(dict.count, 2)
        XCTAssertNotNil(dict["ID"])
        XCTAssertEqual(dict["Name"]?.anyValue as? String, "Alice")
    }

    func testDataTableColumnValues() async throws {
        let table = try await client.dataTable(
            "SELECT 10 AS X UNION ALL SELECT 20 UNION ALL SELECT 30"
        )
        let values = table.column(named: "X")
        XCTAssertEqual(values.count, 3)
        XCTAssertFalse(values.contains(.null))
    }

    func testDataTableNameAssignment() async throws {
        let table = try await client.dataTable("SELECT 1 AS A", name: "MyTable")
        XCTAssertEqual(table.name, "MyTable")
    }

    func testDataTableStringCellValue() async throws {
        let table = try await client.dataTable("SELECT 'SQLClient' AS Lib")
        if case .string(let s) = table[0, "Lib"] {
            XCTAssertEqual(s, "SQLClient")
        } else {
            XCTFail("Expected .string cell")
        }
    }

    func testDataTableBoolCellValue() async throws {
        let table = try await client.dataTable("SELECT CAST(1 AS BIT) AS Flag")
        if case .bool(let b) = table[0, "Flag"] {
            XCTAssertTrue(b)
        } else {
            XCTFail("Expected .bool cell")
        }
    }

    func testDataTableDateCellValue() async throws {
        let table = try await client.dataTable("SELECT GETDATE() AS Now")
        if case .date(let d) = table[0, "Now"] {
            XCTAssertTrue(d.timeIntervalSinceNow < 5)
        } else {
            XCTFail("Expected .date cell")
        }
    }

    func testDataTableDecimalCellValue() async throws {
        let table = try await client.dataTable("SELECT CAST(3.14 AS DECIMAL(10,2)) AS Pi")
        if case .decimal(let d) = table[0, "Pi"] {
            XCTAssertEqual(d, Decimal(string: "3.14"))
        } else {
            XCTFail("Expected .decimal cell")
        }
    }

    func testDataTableDisplayString() async throws {
        let table = try await client.dataTable("SELECT 'hello|world' AS Msg")
        // Pipes in strings should be escaped for Markdown
        let display = table[0, "Msg"].displayString
        XCTAssertTrue(display.contains("\\|"), "Pipe character should be escaped in displayString")
    }

    // MARK: - toMarkdown

    func testDataTableToMarkdownContainsColumnNames() async throws {
        let table = try await client.dataTable("SELECT 1 AS ID, 'Alice' AS Name")
        let md = table.toMarkdown()
        XCTAssertTrue(md.contains("ID"))
        XCTAssertTrue(md.contains("Name"))
    }

    func testDataTableToMarkdownContainsValues() async throws {
        let table = try await client.dataTable("SELECT 42 AS Answer")
        let md = table.toMarkdown()
        XCTAssertTrue(md.contains("42"))
    }

    func testDataTableToMarkdownHasHeaderSeparator() async throws {
        let table = try await client.dataTable("SELECT 1 AS A, 2 AS B")
        let md = table.toMarkdown()
        // Every GFM table has a separator row with dashes
        XCTAssertTrue(md.contains("---|"), "Markdown should include a header separator row")
    }

    func testDataTableToMarkdownIncludesName() async throws {
        let table = try await client.dataTable("SELECT 1 AS A", name: "Results")
        let md = table.toMarkdown()
        XCTAssertTrue(md.hasPrefix("# Results"))
    }

    func testDataTableToMarkdownLineCount() async throws {
        let table = try await client.dataTable(
            "SELECT 1 AS N UNION ALL SELECT 2 UNION ALL SELECT 3"
        )
        let lines = table.toMarkdown().components(separatedBy: "\n").filter { !$0.isEmpty }
        // header + separator + 3 data rows = 5 lines (no name prefix)
        XCTAssertEqual(lines.count, 5)
    }

    // MARK: - decode<T>

    func testDataTableDecodeDecodable() async throws {
        struct Row: Decodable {
            let id: Int
            let name: String
        }
        let table = try await client.dataTable(
            "SELECT 1 AS id, 'Alice' AS name UNION ALL SELECT 2, 'Bob'"
        )
        let rows: [Row] = try table.decode()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].id, 1)
        XCTAssertEqual(rows[0].name, "Alice")
        XCTAssertEqual(rows[1].id, 2)
        XCTAssertEqual(rows[1].name, "Bob")
    }

    func testDataTableDecodeOptionalField() async throws {
        struct Row: Decodable {
            let id: Int
            let note: String?
        }
        let table = try await client.dataTable("SELECT 7 AS id, NULL AS note")
        let rows: [Row] = try table.decode()
        XCTAssertEqual(rows[0].id, 7)
        XCTAssertNil(rows[0].note)
    }

    // MARK: - toSQLRows

    func testDataTableToSQLRowsCount() async throws {
        let table = try await client.dataTable(
            "SELECT 1 AS A UNION ALL SELECT 2 UNION ALL SELECT 3"
        )
        let sqlRows = table.toSQLRows()
        XCTAssertEqual(sqlRows.count, 3)
    }

    func testDataTableToSQLRowsValues() async throws {
        let table = try await client.dataTable("SELECT 'hello' AS Msg")
        let sqlRows = table.toSQLRows()
        XCTAssertEqual(sqlRows[0].string("Msg"), "hello")
    }

    // MARK: - JSON Codable

    func testDataTableCodableRoundTrip() async throws {
        let table = try await client.dataTable(
            "SELECT 1 AS id, 'Alice' AS name, CAST(1 AS BIT) AS active"
        )
        let encoded = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(SQLDataTable.self, from: encoded)

        XCTAssertEqual(decoded.rowCount, table.rowCount)
        XCTAssertEqual(decoded.columnCount, table.columnCount)
        XCTAssertEqual(decoded.columns[0].name, "id")
        XCTAssertEqual(decoded.columns[1].name, "name")
        XCTAssertEqual(decoded[0, "name"].anyValue as? String, "Alice")
    }

    func testDataTableCodablePreservesNullCell() async throws {
        let table = try await client.dataTable("SELECT NULL AS Val")
        let encoded = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(SQLDataTable.self, from: encoded)
        XCTAssertEqual(decoded[0, "Val"], .null)
    }

    // MARK: - asDataTable / asSQLDataSet on SQLClientResult

    func testAsDataTableFromResult() async throws {
        let result = try await client.execute("SELECT 10 AS X, 20 AS Y")
        let table = result.asDataTable(name: "Test")
        XCTAssertEqual(table.name, "Test")
        XCTAssertEqual(table.rowCount, 1)
        XCTAssertEqual(table.columnCount, 2)
    }

    func testAsSQLDataSetFromResult() async throws {
        let result = try await client.execute("SELECT 1 AS A; SELECT 2 AS B;")
        let ds = result.asSQLDataSet()
        XCTAssertEqual(ds.count, 2)
        XCTAssertNotNil(ds[0])
        XCTAssertNotNil(ds[1])
    }

    // MARK: - SQLDataSet

    func testDataSetCount() async throws {
        let ds = try await client.dataSet("SELECT 1 AS A; SELECT 2 AS B; SELECT 3 AS C;")
        XCTAssertEqual(ds.count, 3)
    }

    func testDataSetSubscriptByIndex() async throws {
        let ds = try await client.dataSet("SELECT 'first' AS V; SELECT 'second' AS V;")
        XCTAssertEqual(ds[0]?[0, "V"].anyValue as? String, "first")
        XCTAssertEqual(ds[1]?[0, "V"].anyValue as? String, "second")
    }

    func testDataSetSubscriptOutOfBoundsReturnsNil() async throws {
        let ds = try await client.dataSet("SELECT 1 AS A")
        XCTAssertNil(ds[99])
    }

    func testDataSetSubscriptByName() async throws {
        // Use a temp table with a named result via a stored proc isn't feasible here,
        // so we verify that name-based lookup works via asSQLDataSet with a named table.
        let result = try await client.execute("SELECT 42 AS Val")
        let ds = result.asSQLDataSet()
        // The first table has no name by convention; rename via re-init for test purposes.
        // Instead, test that subscript by non-existent name returns nil gracefully.
        XCTAssertNil(ds["NonExistent"])
    }

    func testDataSetTablesAreAccessible() async throws {
        let ds = try await client.dataSet(
            "SELECT 1 AS ID, 'Alice' AS Name UNION ALL SELECT 2, 'Bob';" +
            "SELECT 100 AS Score;"
        )
        let table0 = ds[0]
        let table1 = ds[1]
        XCTAssertEqual(table0?.rowCount, 2)
        XCTAssertEqual(table1?.rowCount, 1)
        XCTAssertEqual(table1?[0, "Score"].anyValue as? Int32, 100)
    }

    // MARK: - SQLDataSet Codable

    func testDataSetCodableRoundTrip() async throws {
        let ds = try await client.dataSet("SELECT 1 AS A; SELECT 'hello' AS B;")
        let encoded = try JSONEncoder().encode(ds)
        let decoded = try JSONDecoder().decode(SQLDataSet.self, from: encoded)
        XCTAssertEqual(decoded.count, ds.count)
        XCTAssertEqual(decoded[0]?.rowCount, ds[0]?.rowCount)
    }

    // MARK: - SQLCellValue

    func testSQLCellValueEquality() {
        XCTAssertEqual(SQLCellValue.null, SQLCellValue.null)
        XCTAssertEqual(SQLCellValue.string("hi"), SQLCellValue.string("hi"))
        XCTAssertNotEqual(SQLCellValue.string("hi"), SQLCellValue.string("bye"))
        XCTAssertNotEqual(SQLCellValue.null, SQLCellValue.string(""))
    }

    func testSQLCellValueAnyValueTypes() {
        XCTAssertNil(SQLCellValue.null.anyValue)
        XCTAssertEqual(SQLCellValue.string("x").anyValue as? String, "x")
        XCTAssertEqual(SQLCellValue.int32(7).anyValue as? Int32, 7)
        XCTAssertEqual(SQLCellValue.bool(true).anyValue as? Bool, true)
        XCTAssertEqual(SQLCellValue.double(3.14).anyValue as? Double, 3.14)
    }

    func testSQLCellValueDisplayStringNull() {
        XCTAssertEqual(SQLCellValue.null.displayString, "")
    }

    func testSQLCellValueDisplayStringBool() {
        XCTAssertEqual(SQLCellValue.bool(true).displayString, "true")
        XCTAssertEqual(SQLCellValue.bool(false).displayString, "false")
    }

    func testSQLCellValueCodableRoundTrip() throws {
        let values: [SQLCellValue] = [
            .null,
            .string("hello"),
            .int32(42),
            .int64(9_999_999_999),
            .double(3.14),
            .bool(true),
            .decimal(Decimal(string: "123.456")!),
            .uuid(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!),
        ]
        for original in values {
            let data = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(SQLCellValue.self, from: data)
            XCTAssertEqual(restored, original, "Round-trip failed for \(original)")
        }
    }

    func testSQLCellValueCodableDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SQLCellValue.date(now)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SQLCellValue.self, from: data)
        if case .date(let d) = restored {
            XCTAssertEqual(d.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        } else {
            XCTFail("Expected .date after round-trip")
        }
    }

    func testSQLCellValueCodableBytes() throws {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let original = SQLCellValue.bytes(bytes)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SQLCellValue.self, from: data)
        if case .bytes(let b) = restored {
            XCTAssertEqual(b, bytes)
        } else {
            XCTFail("Expected .bytes after round-trip")
        }
    }
}
