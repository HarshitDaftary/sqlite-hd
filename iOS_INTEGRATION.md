# iOS/Swift Integration for Custom SQLite with SQLITE_ENABLE_QUEUE

This guide shows how to integrate your custom SQLite build with SQLITE_ENABLE_QUEUE support into iOS applications using Swift.

## 🎯 **Overview**

There are several approaches to use your custom SQLite in iOS:

1. **Framework Integration** (Recommended) - Build as iOS framework
2. **Static Library** - Compile directly into your app
3. **Swift Package Manager** - Create a SPM package
4. **Xcframework** - Universal framework for all Apple platforms

## 🏗️ **Approach 1: iOS Framework (Recommended)**

### Step 1: Build Custom SQLite for iOS

First, we need to cross-compile your SQLite for iOS architectures.

### Step 2: Create Xcode Project

Here's a complete Swift wrapper for your custom SQLite:

## 📱 **Swift Wrapper Code**

```swift
import Foundation
import SQLite3

/// Custom SQLite wrapper with SQLITE_ENABLE_QUEUE support
public class CustomSQLite {
    private var db: OpaquePointer?
    private let dbPath: String
    
    /// SQLite result codes
    public enum SQLiteError: Error {
        case openDatabase(message: String)
        case prepare(message: String)
        case step(message: String)
        case bind(message: String)
        case queueNotSupported
    }
    
    public init(path: String) throws {
        self.dbPath = path
        try openDatabase()
        try configureDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Operations
    
    private func openDatabase() throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw SQLiteError.openDatabase(message: message)
        }
    }
    
    private func configureDatabase() throws {
        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode=WAL;")
        
        // Set busy timeout
        try execute("PRAGMA busy_timeout=30000;")
        
        // Enable write queue if available
        try setWriteQueueEnabled(true)
    }
    
    public func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    // MARK: - Write Queue Support
    
    /// Check if write queue is enabled
    public func isWriteQueueEnabled() -> Bool {
        do {
            let result = try queryScalar("PRAGMA write_queue;")
            return result == "1"
        } catch {
            return false
        }
    }
    
    /// Enable or disable write queue
    public func setWriteQueueEnabled(_ enabled: Bool) throws {
        let value = enabled ? "ON" : "OFF"
        try execute("PRAGMA write_queue = \(value);")
    }
    
    /// Get write queue status information
    public func getWriteQueueInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        do {
            info["enabled"] = try queryScalar("PRAGMA write_queue;")
            info["supported"] = true
        } catch {
            info["supported"] = false
            info["error"] = error.localizedDescription
        }
        
        return info
    }
    
    // MARK: - SQL Execution
    
    /// Execute SQL statement without return value
    public func execute(_ sql: String) throws {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: message)
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.step(message: message)
        }
    }
    
    /// Execute SQL with parameters
    public func execute(_ sql: String, parameters: [Any]) throws {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: message)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            
            switch parameter {
            case let stringValue as String:
                sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            case let intValue as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(intValue))
            case let doubleValue as Double:
                sqlite3_bind_double(statement, bindIndex, doubleValue)
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            default:
                let stringValue = String(describing: parameter)
                sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            }
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.step(message: message)
        }
    }
    
    /// Query for multiple rows
    public func query(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        var results: [[String: Any]] = []
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: message)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            
            switch parameter {
            case let stringValue as String:
                sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            case let intValue as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(intValue))
            case let doubleValue as Double:
                sqlite3_bind_double(statement, bindIndex, doubleValue)
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            default:
                let stringValue = String(describing: parameter)
                sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            }
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(statement)
            var row: [String: Any] = [:]
            
            for columnIndex in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, columnIndex))
                
                switch sqlite3_column_type(statement, columnIndex) {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, columnIndex)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, columnIndex)
                case SQLITE_TEXT:
                    row[columnName] = String(cString: sqlite3_column_text(statement, columnIndex))
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    row[columnName] = NSNull()
                }
            }
            
            results.append(row)
        }
        
        return results
    }
    
    /// Query for single scalar value
    public func queryScalar(_ sql: String, parameters: [Any] = []) throws -> String? {
        let results = try query(sql, parameters: parameters)
        guard let firstRow = results.first,
              let firstValue = firstRow.values.first else {
            return nil
        }
        
        if firstValue is NSNull {
            return nil
        }
        
        return String(describing: firstValue)
    }
    
    // MARK: - Transaction Support
    
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN TRANSACTION;")
        
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            try execute("ROLLBACK;")
            throw error
        }
    }
}

// MARK: - Convenience Extensions

extension CustomSQLite {
    
    /// Create table helper
    public func createTable(_ name: String, columns: [String]) throws {
        let columnsSQL = columns.joined(separator: ", ")
        let sql = "CREATE TABLE IF NOT EXISTS \(name) (\(columnsSQL));"
        try execute(sql)
    }
    
    /// Insert helper
    public func insert(into table: String, values: [String: Any]) throws {
        let columns = values.keys.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders));"
        
        let parameters = Array(values.values)
        try execute(sql, parameters: parameters)
    }
    
    /// Update helper
    public func update(table: String, set values: [String: Any], where condition: String, parameters: [Any] = []) throws {
        let setClause = values.keys.map { "\($0) = ?" }.joined(separator: ", ")
        let sql = "UPDATE \(table) SET \(setClause) WHERE \(condition);"
        
        let allParameters = Array(values.values) + parameters
        try execute(sql, parameters: allParameters)
    }
    
    /// Delete helper
    public func delete(from table: String, where condition: String, parameters: [Any] = []) throws {
        let sql = "DELETE FROM \(table) WHERE \(condition);"
        try execute(sql, parameters: parameters)
    }
}
```

## 📱 **Usage Example**

```swift
import UIKit

class ViewController: UIViewController {
    private var database: CustomSQLite?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupDatabase()
        demonstrateWriteQueue()
    }
    
    private func setupDatabase() {
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                       in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("app.db").path
            
            database = try CustomSQLite(path: dbPath)
            
            // Create tables
            try database?.createTable("users", columns: [
                "id INTEGER PRIMARY KEY AUTOINCREMENT",
                "name TEXT NOT NULL",
                "email TEXT UNIQUE",
                "created_at DATETIME DEFAULT CURRENT_TIMESTAMP"
            ])
            
            print("✅ Database initialized successfully")
            
        } catch {
            print("❌ Database setup failed: \(error)")
        }
    }
    
    private func demonstrateWriteQueue() {
        guard let db = database else { return }
        
        do {
            // Check write queue support
            let queueInfo = db.getWriteQueueInfo()
            print("Write Queue Info: \(queueInfo)")
            
            if db.isWriteQueueEnabled() {
                print("✅ Write queue is enabled")
            } else {
                print("⚠️ Write queue is not enabled")
            }
            
            // Insert some test data
            try db.insert(into: "users", values: [
                "name": "John Doe",
                "email": "john@example.com"
            ])
            
            try db.insert(into: "users", values: [
                "name": "Jane Smith", 
                "email": "jane@example.com"
            ])
            
            // Query data
            let users = try db.query("SELECT * FROM users ORDER BY id;")
            print("Users: \(users)")
            
            // Demonstrate transaction
            try db.transaction {
                try db.insert(into: "users", values: [
                    "name": "Bob Wilson",
                    "email": "bob@example.com"
                ])
                
                try db.insert(into: "users", values: [
                    "name": "Alice Brown",
                    "email": "alice@example.com" 
                ])
            }
            
            let userCount = try db.queryScalar("SELECT COUNT(*) FROM users;")
            print("Total users: \(userCount ?? "0")")
            
        } catch {
            print("❌ Database operation failed: \(error)")
        }
    }
    
    // Demonstrate concurrent writes
    private func testConcurrentWrites() {
        guard let db = database else { return }
        
        let dispatchGroup = DispatchGroup()
        
        for threadId in 0..<5 {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .background).async {
                do {
                    for i in 0..<10 {
                        try db.insert(into: "users", values: [
                            "name": "User \(threadId)-\(i)",
                            "email": "user\(threadId)\(i)@example.com"
                        ])
                        print("Thread \(threadId): inserted user \(i)")
                    }
                } catch {
                    print("Thread \(threadId) error: \(error)")
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            do {
                let count = try db.queryScalar("SELECT COUNT(*) FROM users;")
                print("Final user count: \(count ?? "0")")
            } catch {
                print("Error getting final count: \(error)")
            }
        }
    }
}
```

## 🛠️ **Build Instructions**

Create these files in your iOS project:

1. **CustomSQLite.swift** - The main wrapper class
2. **CustomSQLite.h** - Bridge header if needed
3. **Your custom SQLite library** - Compiled for iOS

### Xcode Project Setup:

1. Add your custom SQLite library to the project
2. Link against your custom SQLite instead of system SQLite
3. Add bridging header if using Objective-C interop

## 📦 **Distribution Options**

### Option 1: Direct Integration
- Copy the Swift files directly into the iOS project
- Include your custom SQLite library

### Option 2: Framework
- Create an iOS framework containing your SQLite + Swift wrapper
- Distribute as .framework bundle

### Option 3: Swift Package Manager
- Create SPM package with your SQLite + Swift wrapper
- Easy integration via Xcode

### Option 4: CocoaPods
- Create podspec for your custom SQLite
- Distribute via CocoaPods

Would you like me to create any of these specific distribution methods or help with the iOS compilation process?