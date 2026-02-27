import XCTest
@testable import SQLClientSwift

final class SQLRPCTests: XCTestCase {
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

    func testRPCWithOutputParameters() async throws {
        let name = "RPC_Test_Proc"
        // Create a persistent procedure for testing RPC (temp procedures might have scope issues with RPC)
        try? await client.run("DROP PROCEDURE \(name)")
        try await client.run("""
            CREATE PROCEDURE \(name) @InVal INT, @OutVal INT OUTPUT AS
            BEGIN
                SET @OutVal = @InVal * 2;
                RETURN 77;
            END;
        """)
        
        defer {
            Task {
                let c = SQLClient()
                try? await c.connect(server: host, username: username, password: password, database: database.isEmpty ? nil : database)
                _ = try? await c.run("DROP PROCEDURE \(name)")
                await c.disconnect()
            }
        }

        let params = [
            SQLParameter(name: "@InVal", value: Int32(21), isOutput: false),
            SQLParameter(name: "@OutVal", value: Int32(0), isOutput: true)
        ]

        let result = try await client.executeRPC(name, parameters: params)

        // Check output parameters captured via RPC
        XCTAssertEqual((result.outputParameters["@OutVal"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual(result.returnStatus, 77)
    }

    func testRPCWithStrings() async throws {
        let name = "RPC_String_Test_Proc"
        try? await client.run("DROP PROCEDURE \(name)")
        try await client.run("""
            CREATE PROCEDURE \(name) @InStr NVARCHAR(50), @OutStr NVARCHAR(50) OUTPUT AS
            BEGIN
                SET @OutStr = 'Hello ' + @InStr;
            END;
        """)
        
        defer {
            Task {
                let c = SQLClient()
                try? await c.connect(server: host, username: username, password: password, database: database.isEmpty ? nil : database)
                _ = try? await c.run("DROP PROCEDURE \(name)")
                await c.disconnect()
            }
        }

        let params = [
            SQLParameter(name: "@InStr", value: "World", isOutput: false),
            SQLParameter(name: "@OutStr", value: "", isOutput: true)
        ]

        let result = try await client.executeRPC(name, parameters: params)

        XCTAssertEqual(result.outputParameters["@OutStr"] as? String, "Hello World")
    }
}
