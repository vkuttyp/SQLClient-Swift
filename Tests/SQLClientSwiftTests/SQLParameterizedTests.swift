import XCTest
@testable import SQLClientSwift

final class SQLParameterizedTests: XCTestCase {
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
    }

    override func tearDown() async throws {
        if let c = client {
            await c.disconnect()
        }
    }

    func testExecuteParameterized() async throws {
        let sql = "SELECT @Val + 1 as Result, @Str as Msg"
        let params = [
            SQLParameter(name: "@Val", value: Int32(10), isOutput: false),
            SQLParameter(name: "@Str", value: "Hello", isOutput: false)
        ]
        
        let result = try await client.executeParameterized(sql, parameters: params)
        
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].int("Result"), 11)
        XCTAssertEqual(result.rows[0].string("Msg"), "Hello")
    }

    func testParameterizedOutput() async throws {
        let sql = "SET @Out = @In * 10"
        let params = [
            SQLParameter(name: "@In", value: Int32(5), isOutput: false),
            SQLParameter(name: "@Out", value: Int32(0), isOutput: true)
        ]
        
        let result = try await client.executeParameterized(sql, parameters: params)
        
        XCTAssertEqual((result.outputParameters["@Out"] as? NSNumber)?.intValue, 50)
    }
}
