import XCTest
@testable import CustomSQLite

final class CustomSQLiteTests: XCTestCase {
    private var tempDBPath: String!
    private var database: CustomSQLite!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary database file
        let tempDir = NSTemporaryDirectory()
        tempDBPath = (tempDir as NSString).appendingPathComponent("test_\(UUID().uuidString).db")
        
        do {
            database = try CustomSQLite(path: tempDBPath)
        } catch {
            XCTFail("Failed to create test database: \(error)")
        }
    }
    
    override func tearDown() {
        database?.closeDatabase()
        
        // Clean up temporary file
        if FileManager.default.fileExists(atPath: tempDBPath) {
            try? FileManager.default.removeItem(atPath: tempDBPath)
        }
        
        super.tearDown()
    }
    
    func testDatabaseInitialization() {
        XCTAssertNotNil(database)
        
        // Test database info
        let info = database.getDatabaseInfo()
        XCTAssertNotNil(info["sqlite_version"])
        XCTAssertEqual(info["path"] as? String, tempDBPath)
    }
    
    func testWriteQueueSupport() {
        // Test that write queue is available
        let queueInfo = database.getWriteQueueInfo()
        
        if queueInfo["supported"] as? Bool == true {
            // If queue is supported, test enabling/disabling
            XCTAssertNoThrow(try database.setWriteQueueEnabled(true))
            XCTAssertTrue(database.isWriteQueueEnabled())
            
            XCTAssertNoThrow(try database.setWriteQueueEnabled(false))
            XCTAssertFalse(database.isWriteQueueEnabled())
            
            // Re-enable for other tests
            XCTAssertNoThrow(try database.setWriteQueueEnabled(true))
        } else {
            print("Write queue not supported in this build")
        }
    }
    
    func testTableCreation() {
        XCTAssertNoThrow(try database.createTable("test_users", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT NOT NULL",
            "email TEXT UNIQUE"
        ]))
        
        // Verify table exists
        let tables = try? database.getTableNames()
        XCTAssertTrue(tables?.contains("test_users") == true)
    }
    
    func testInsertAndQuery() {
        // Create test table
        try! database.createTable("test_users", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT NOT NULL",
            "email TEXT"
        ])
        
        // Insert test data
        XCTAssertNoThrow(try database.insert(into: "test_users", values: [
            "name": "John Doe",
            "email": "john@example.com"
        ]))
        
        XCTAssertNoThrow(try database.insert(into: "test_users", values: [
            "name": "Jane Smith",
            "email": "jane@example.com"
        ]))
        
        // Query data
        let users = try? database.query("SELECT * FROM test_users ORDER BY id;")
        XCTAssertNotNil(users)
        XCTAssertEqual(users?.count, 2)
        
        if let firstUser = users?.first {
            XCTAssertEqual(firstUser["name"] as? String, "John Doe")
            XCTAssertEqual(firstUser["email"] as? String, "john@example.com")
        }
        
        // Test scalar query
        let count = try? database.queryScalar("SELECT COUNT(*) FROM test_users;")
        XCTAssertEqual(count, "2")
    }
    
    func testConcurrentWrites() {
        // Create test table
        try! database.createTable("concurrent_test", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "thread_id INTEGER",
            "value INTEGER"
        ])
        
        let expectation = XCTestExpectation(description: "Concurrent writes completed")
        let dispatchGroup = DispatchGroup()
        
        var successCount = 0
        var errorCount = 0
        let lockQueue = DispatchQueue(label: "counter")
        
        // Launch multiple concurrent writers
        for threadId in 0..<5 {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .background).async {
                for value in 0..<10 {
                    do {
                        try self.database.insert(into: "concurrent_test", values: [
                            "thread_id": threadId,
                            "value": value
                        ])
                        
                        lockQueue.async {
                            successCount += 1
                        }
                    } catch {
                        lockQueue.async {
                            errorCount += 1
                        }
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
        
        // Check results
        let totalRecords = try? database.count(in: "concurrent_test")
        
        print("Concurrent write test results:")
        print("  Success count: \(successCount)")
        print("  Error count: \(errorCount)")
        print("  Records in DB: \(totalRecords ?? 0)")
        
        // With write queue, we should have high success rate
        let expectedTotal = 5 * 10 // 5 threads × 10 writes
        XCTAssertGreaterThan(successCount, expectedTotal / 2, "Should have reasonable success rate")
        XCTAssertEqual(totalRecords, successCount, "Database should contain all successful writes")
    }
    
    func testTransactions() {
        // Create test table
        try! database.createTable("transaction_test", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "value TEXT"
        ])
        
        // Test successful transaction
        XCTAssertNoThrow(try database.transaction {
            try database.insert(into: "transaction_test", values: ["value": "test1"])
            try database.insert(into: "transaction_test", values: ["value": "test2"])
        })
        
        let count = try? database.count(in: "transaction_test")
        XCTAssertEqual(count, 2)
        
        // Test rollback on error
        XCTAssertThrowsError(try database.transaction {
            try database.insert(into: "transaction_test", values: ["value": "test3"])
            // Simulate error by trying to insert into non-existent table
            try database.insert(into: "non_existent_table", values: ["value": "test4"])
        })
        
        // Count should still be 2 (rollback occurred)
        let countAfterRollback = try? database.count(in: "transaction_test")
        XCTAssertEqual(countAfterRollback, 2)
    }
    
    func testUpdateAndDelete() {
        // Create and populate test table
        try! database.createTable("update_test", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT",
            "status TEXT"
        ])
        
        try! database.insert(into: "update_test", values: ["name": "John", "status": "active"])
        try! database.insert(into: "update_test", values: ["name": "Jane", "status": "inactive"])
        
        // Test update
        XCTAssertNoThrow(try database.update(
            table: "update_test",
            set: ["status": "active"],
            where: "name = ?",
            parameters: ["Jane"]
        ))
        
        let updatedUser = try? database.query("SELECT * FROM update_test WHERE name = 'Jane';")
        XCTAssertEqual(updatedUser?.first?["status"] as? String, "active")
        
        // Test delete
        XCTAssertNoThrow(try database.delete(
            from: "update_test",
            where: "name = ?",
            parameters: ["John"]
        ))
        
        let remainingCount = try? database.count(in: "update_test")
        XCTAssertEqual(remainingCount, 1)
    }
    
    func testParameterBinding() {
        // Create test table
        try! database.createTable("param_test", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "text_val TEXT",
            "int_val INTEGER",
            "double_val REAL",
            "bool_val INTEGER"
        ])
        
        // Test various parameter types
        XCTAssertNoThrow(try database.execute(
            "INSERT INTO param_test (text_val, int_val, double_val, bool_val) VALUES (?, ?, ?, ?);",
            parameters: ["test string", 42, 3.14159, true]
        ))
        
        let result = try? database.query("SELECT * FROM param_test;")
        XCTAssertNotNil(result)
        
        if let row = result?.first {
            XCTAssertEqual(row["text_val"] as? String, "test string")
            XCTAssertEqual(row["int_val"] as? Int64, 42)
            XCTAssertEqual(row["double_val"] as? Double, 3.14159, accuracy: 0.00001)
            XCTAssertEqual(row["bool_val"] as? Int64, 1) // Bool stored as 1
        }
    }
}