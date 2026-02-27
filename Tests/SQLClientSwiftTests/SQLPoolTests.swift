import XCTest
@testable import SQLClientSwift

final class SQLPoolTests: XCTestCase {
    private func env(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? "" }
    private var host: String { env("HOST") }
    private var username: String { env("USERNAME") }
    private var password: String { env("PASSWORD") }
    private var database: String { env("DATABASE") }
    private var canConnect: Bool { !host.isEmpty && !username.isEmpty && !password.isEmpty }

    func testPoolAcquireRelease() async throws {
        guard canConnect else { throw XCTSkip("No connection info") }
        
        let options = SQLClientConnectionOptions(server: host, username: username, password: password, database: database.isEmpty ? nil : database)
        let pool = SQLClientPool(options: options, maxPoolSize: 2)
        
        // Acquire 1
        let client1 = try await pool.acquire()
        let isConnected1 = await client1.isConnected
        let poolSize1 = await pool.currentPoolSize
        XCTAssertTrue(isConnected1)
        XCTAssertEqual(poolSize1, 1)
        
        // Acquire 2
        let client2 = try await pool.acquire()
        let isConnected2 = await client2.isConnected
        let poolSize2 = await pool.currentPoolSize
        XCTAssertTrue(isConnected2)
        XCTAssertEqual(poolSize2, 2)
        
        // Release 1
        await pool.release(client1)
        let poolSize3 = await pool.currentPoolSize
        XCTAssertEqual(poolSize3, 2) // One in pool, one checked out
        
        // Acquire again (should reuse client1)
        let client3 = try await pool.acquire()
        XCTAssertTrue(client3 === client1)
        
        await pool.release(client2)
        await pool.release(client3)
        await pool.disconnectAll()
    }
    
    func testPoolConcurrentAccess() async throws {
        guard canConnect else { throw XCTSkip("No connection info") }
        
        let options = SQLClientConnectionOptions(server: host, username: username, password: password, database: database.isEmpty ? nil : database)
        let pool = SQLClientPool(options: options, maxPoolSize: 3)
        
        // Run 10 concurrent queries
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 1...10 {
                group.addTask {
                    try await pool.withClient { client in
                        let rows = try await client.query("SELECT \(i) AS val")
                        return rows[0].int("val") ?? 0
                    }
                }
            }
            
            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }
            XCTAssertEqual(results.sorted(), Array(1...10))
        }
        
        await pool.disconnectAll()
    }
}
