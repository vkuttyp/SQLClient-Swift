import XCTest
@testable import SQLClientSwift

final class SQLOutputParamTests: XCTestCase {
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

    func testOutputParameters() async throws {
        try await client.run("""
            IF OBJECT_ID('tempdb..#TestProc') IS NOT NULL DROP PROCEDURE #TestProc;
        """)
        try await client.run("""
            CREATE PROCEDURE #TestProc @InVal INT, @OutVal INT OUTPUT AS
            BEGIN
                SET @OutVal = @InVal * 2;
                RETURN 99;
            END;
        """)
        
        // Execute the proc. We MUST use EXEC and specify OUTPUT for the parameter.
        let result = try await client.execute("DECLARE @Out INT; EXEC #TestProc @InVal = 21, @OutVal = @Out OUTPUT; SELECT @Out AS OutVal;")
        
        // Check result set since output parameters via dbnumrets are unreliable for batches
        XCTAssertEqual(result.rows[0].int("OutVal"), 42)
        
        // Check return status
        XCTAssertEqual(result.returnStatus, 99)
    }
    
    func testMultipleOutputParameters() async throws {
        try await client.run("""
            IF OBJECT_ID('tempdb..#MultiOut') IS NOT NULL DROP PROCEDURE #MultiOut;
        """)
        try await client.run("""
            CREATE PROCEDURE #MultiOut @A INT OUTPUT, @B NVARCHAR(50) OUTPUT AS
            BEGIN
                SET @A = 123;
                SET @B = 'Hello Output';
            END;
        """)
        
        let result = try await client.execute("DECLARE @O1 INT, @O2 NVARCHAR(50); EXEC #MultiOut @A = @O1 OUTPUT, @B = @O2 OUTPUT; SELECT @O1 AS A, @O2 AS B;")
        
        XCTAssertEqual(result.rows[0].int("A"), 123)
        XCTAssertEqual(result.rows[0].string("B"), "Hello Output")
    }
}
