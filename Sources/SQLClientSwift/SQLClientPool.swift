import Foundation

/// A thread-safe connection pool for SQLClient instances.
/// Useful for high-concurrency applications where a single connection would be a bottleneck.
public actor SQLClientPool: Sendable {
    private let options: SQLClientConnectionOptions
    private let maxPoolSize: Int
    
    private var pool: [SQLClient] = []
    private var checkedOutCount: Int = 0
    private var waiters: [CheckedContinuation<SQLClient, Error>] = []
    
    public init(options: SQLClientConnectionOptions, maxPoolSize: Int = 10) {
        self.options = options
        self.maxPoolSize = maxPoolSize
    }
    
    /// Acquires a connected SQLClient from the pool.
    /// If no client is available and the pool is not full, a new connection is established.
    /// If the pool is full, this method waits until a client is released.
    public func acquire() async throws -> SQLClient {
        // First try to take from the pool
        if !pool.isEmpty {
            checkedOutCount += 1
            let client = pool.removeLast()
            return client
        }
        
        // If pool is empty, check if we can create a new connection
        if checkedOutCount < maxPoolSize {
            checkedOutCount += 1
            do {
                let client = SQLClient()
                try await client.connect(options: options)
                return client
            } catch {
                checkedOutCount -= 1
                throw error
            }
        }
        
        // Otherwise, wait for a client to be released
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    /// Releases a SQLClient back to the pool for reuse.
    public func release(_ client: SQLClient) async {
        // First check if there's someone waiting for it
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: client)
            return
        }
        
        // Otherwise, put it back into the pool
        checkedOutCount -= 1
        pool.append(client)
    }
    
    /// Executes a closure with a pooled client, ensuring it is returned to the pool afterwards.
    public func withClient<T: Sendable>(_ body: @Sendable @escaping (SQLClient) async throws -> T) async throws -> T {
        let client = try await acquire()
        do {
            let result = try await body(client)
            await release(client)
            return result
        } catch {
            await release(client)
            throw error
        }
    }
    
    /// Disconnects all clients in the pool.
    public func disconnectAll() async {
        let allClients = pool
        pool.removeAll()
        checkedOutCount -= allClients.count
        for client in allClients {
            await client.disconnect()
        }
        // Note: currently checked-out clients are not handled here.
        // They will be disconnected when they are released or when they are deallocated.
    }
    
    public var currentPoolSize: Int {
        pool.count + checkedOutCount
    }
}
