//
//  CustomSQLite.swift
//  Custom SQLite wrapper with SQLITE_ENABLE_QUEUE support for iOS
//
//  This Swift wrapper provides easy access to your custom SQLite library
//  with write queue functionality for improved concurrent performance.
//

import Foundation
import SQLite3

/// Custom SQLite wrapper with SQLITE_ENABLE_QUEUE support
public class CustomSQLite {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.custom.sqlite", qos: .utility)
    
    /// SQLite result codes and errors
    public enum SQLiteError: Error {
        case openDatabase(message: String)
        case prepare(message: String)
        case step(message: String)
        case bind(message: String)
        case queueNotSupported
        case invalidPath
        case databaseClosed
        
        public var localizedDescription: String {
            switch self {
            case .openDatabase(let message):
                return "Failed to open database: \(message)"
            case .prepare(let message):
                return "Failed to prepare statement: \(message)"
            case .step(let message):
                return "Failed to execute statement: \(message)"
            case .bind(let message):
                return "Failed to bind parameter: \(message)"
            case .queueNotSupported:
                return "Write queue is not supported in this SQLite build"
            case .invalidPath:
                return "Invalid database path"
            case .databaseClosed:
                return "Database connection is closed"
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize CustomSQLite with database path
    /// - Parameter path: Path to SQLite database file
    /// - Throws: SQLiteError if unable to open database
    public init(path: String) throws {
        guard !path.isEmpty else {
            throw SQLiteError.invalidPath
        }
        
        self.dbPath = path
        try openDatabase()
        try configureDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Management
    
    private func openDatabase() throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openDatabase(message: message)
        }
    }
    
    private func configureDatabase() throws {
        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode=WAL;")
        
        // Set busy timeout (30 seconds)
        try execute("PRAGMA busy_timeout=30000;")
        
        // Enable write queue if available
        do {
            try setWriteQueueEnabled(true)
        } catch {
            // Write queue might not be available, continue anyway
            print("Warning: Write queue not available: \(error)")
        }
    }
    
    public func closeDatabase() {
        queue.sync {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
        }
    }
    
    // MARK: - Write Queue Support
    
    /// Check if write queue is enabled
    /// - Returns: True if write queue is enabled, false otherwise
    public func isWriteQueueEnabled() -> Bool {
        do {
            let result = try queryScalar("PRAGMA write_queue;")
            return result == "1"
        } catch {
            return false
        }
    }
    
    /// Enable or disable write queue
    /// - Parameter enabled: True to enable, false to disable
    /// - Throws: SQLiteError if operation fails
    public func setWriteQueueEnabled(_ enabled: Bool) throws {
        let value = enabled ? "ON" : "OFF"
        try execute("PRAGMA write_queue = \(value);")
    }
    
    /// Get comprehensive write queue information
    /// - Returns: Dictionary containing queue status and information
    public func getWriteQueueInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        do {
            let status = try queryScalar("PRAGMA write_queue;")
            info["enabled"] = status == "1"
            info["status_value"] = status
            info["supported"] = true
        } catch {
            info["supported"] = false
            info["error"] = error.localizedDescription
        }
        
        return info
    }
    
    // MARK: - SQL Execution
    
    /// Execute SQL statement without return value
    /// - Parameter sql: SQL statement to execute
    /// - Throws: SQLiteError if execution fails
    public func execute(_ sql: String) throws {
        try queue.sync {
            try _execute(sql)
        }
    }
    
    /// Execute SQL statement with parameters
    /// - Parameters:
    ///   - sql: SQL statement with parameter placeholders
    ///   - parameters: Array of parameters to bind
    /// - Throws: SQLiteError if execution fails
    public func execute(_ sql: String, parameters: [Any]) throws {
        try queue.sync {
            try _execute(sql, parameters: parameters)
        }
    }
    
    private func _execute(_ sql: String, parameters: [Any] = []) throws {
        guard db != nil else {
            throw SQLiteError.databaseClosed
        }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: message)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters if provided
        if !parameters.isEmpty {
            try bindParameters(to: statement, parameters: parameters)
        }
        
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.step(message: message)
        }
    }
    
    /// Query for multiple rows
    /// - Parameters:
    ///   - sql: SELECT statement
    ///   - parameters: Optional parameters to bind
    /// - Returns: Array of dictionaries representing rows
    /// - Throws: SQLiteError if query fails
    public func query(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        return try queue.sync {
            try _query(sql, parameters: parameters)
        }
    }
    
    private func _query(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        guard db != nil else {
            throw SQLiteError.databaseClosed
        }
        
        var statement: OpaquePointer?
        var results: [[String: Any]] = []
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: message)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters if provided
        if !parameters.isEmpty {
            try bindParameters(to: statement, parameters: parameters)
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let row = extractRow(from: statement)
            results.append(row)
        }
        
        return results
    }
    
    /// Query for single scalar value
    /// - Parameters:
    ///   - sql: SQL statement returning single value
    ///   - parameters: Optional parameters to bind
    /// - Returns: String representation of result, or nil if no result
    /// - Throws: SQLiteError if query fails
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
    
    // MARK: - Helper Methods
    
    private func bindParameters(to statement: OpaquePointer?, parameters: [Any]) throws {
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            let result: Int32
            
            switch parameter {
            case let stringValue as String:
                result = sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            case let intValue as Int:
                result = sqlite3_bind_int64(statement, bindIndex, Int64(intValue))
            case let int32Value as Int32:
                result = sqlite3_bind_int(statement, bindIndex, int32Value)
            case let int64Value as Int64:
                result = sqlite3_bind_int64(statement, bindIndex, int64Value)
            case let doubleValue as Double:
                result = sqlite3_bind_double(statement, bindIndex, doubleValue)
            case let floatValue as Float:
                result = sqlite3_bind_double(statement, bindIndex, Double(floatValue))
            case let boolValue as Bool:
                result = sqlite3_bind_int(statement, bindIndex, boolValue ? 1 : 0)
            case is NSNull:
                result = sqlite3_bind_null(statement, bindIndex)
            case Optional<Any>.none:
                result = sqlite3_bind_null(statement, bindIndex)
            default:
                // Convert to string as fallback
                let stringValue = String(describing: parameter)
                result = sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
            }
            
            guard result == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.bind(message: message)
            }
        }
    }
    
    private func extractRow(from statement: OpaquePointer?) -> [String: Any] {
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
                if let cString = sqlite3_column_text(statement, columnIndex) {
                    row[columnName] = String(cString: cString)
                } else {
                    row[columnName] = ""
                }
            case SQLITE_BLOB:
                let dataSize = sqlite3_column_bytes(statement, columnIndex)
                if let dataPointer = sqlite3_column_blob(statement, columnIndex) {
                    row[columnName] = Data(bytes: dataPointer, count: Int(dataSize))
                } else {
                    row[columnName] = Data()
                }
            case SQLITE_NULL:
                row[columnName] = NSNull()
            default:
                row[columnName] = NSNull()
            }
        }
        
        return row
    }
    
    // MARK: - Transaction Support
    
    /// Execute multiple operations in a transaction
    /// - Parameter block: Block containing operations to execute
    /// - Returns: Result of the block
    /// - Throws: SQLiteError or any error from the block
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
    
    /// Execute operations in a transaction (async version)
    /// - Parameters:
    ///   - block: Block containing operations to execute
    ///   - completion: Completion handler with result
    public func transaction<T>(_ block: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            do {
                let result = try self.transaction(block)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension CustomSQLite {
    
    /// Create table helper
    /// - Parameters:
    ///   - name: Table name
    ///   - columns: Array of column definitions
    /// - Throws: SQLiteError if creation fails
    public func createTable(_ name: String, columns: [String]) throws {
        let columnsSQL = columns.joined(separator: ", ")
        let sql = "CREATE TABLE IF NOT EXISTS \(name) (\(columnsSQL));"
        try execute(sql)
    }
    
    /// Insert helper
    /// - Parameters:
    ///   - table: Table name
    ///   - values: Dictionary of column names to values
    /// - Throws: SQLiteError if insertion fails
    public func insert(into table: String, values: [String: Any]) throws {
        let columns = values.keys.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders));"
        
        let parameters = Array(values.values)
        try execute(sql, parameters: parameters)
    }
    
    /// Update helper
    /// - Parameters:
    ///   - table: Table name
    ///   - values: Dictionary of column names to new values
    ///   - condition: WHERE clause condition
    ///   - parameters: Parameters for the WHERE clause
    /// - Throws: SQLiteError if update fails
    public func update(table: String, set values: [String: Any], where condition: String, parameters: [Any] = []) throws {
        let setClause = values.keys.map { "\($0) = ?" }.joined(separator: ", ")
        let sql = "UPDATE \(table) SET \(setClause) WHERE \(condition);"
        
        let allParameters = Array(values.values) + parameters
        try execute(sql, parameters: allParameters)
    }
    
    /// Delete helper
    /// - Parameters:
    ///   - table: Table name
    ///   - condition: WHERE clause condition
    ///   - parameters: Parameters for the WHERE clause
    /// - Throws: SQLiteError if deletion fails
    public func delete(from table: String, where condition: String, parameters: [Any] = []) throws {
        let sql = "DELETE FROM \(table) WHERE \(condition);"
        try execute(sql, parameters: parameters)
    }
    
    /// Count rows in table
    /// - Parameters:
    ///   - table: Table name
    ///   - condition: Optional WHERE clause
    ///   - parameters: Parameters for WHERE clause
    /// - Returns: Number of rows
    /// - Throws: SQLiteError if query fails
    public func count(in table: String, where condition: String? = nil, parameters: [Any] = []) throws -> Int {
        var sql = "SELECT COUNT(*) FROM \(table)"
        if let condition = condition {
            sql += " WHERE \(condition)"
        }
        sql += ";"
        
        let result = try queryScalar(sql, parameters: parameters)
        return Int(result ?? "0") ?? 0
    }
}

// MARK: - Debug and Information

extension CustomSQLite {
    
    /// Get database file information
    /// - Returns: Dictionary with database information
    public func getDatabaseInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        info["path"] = dbPath
        info["exists"] = FileManager.default.fileExists(atPath: dbPath)
        
        do {
            let version = try queryScalar("SELECT sqlite_version();")
            info["sqlite_version"] = version
        } catch {
            info["sqlite_version"] = "unknown"
        }
        
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? NSNumber
            info["file_size"] = fileSize?.intValue ?? 0
        } catch {
            info["file_size"] = 0
        }
        
        info["write_queue"] = getWriteQueueInfo()
        
        return info
    }
    
    /// Get list of tables in database
    /// - Returns: Array of table names
    /// - Throws: SQLiteError if query fails
    public func getTableNames() throws -> [String] {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        let results = try query(sql)
        return results.compactMap { $0["name"] as? String }
    }
    
    /// Get schema for a table
    /// - Parameter tableName: Name of the table
    /// - Returns: CREATE TABLE statement
    /// - Throws: SQLiteError if query fails
    public func getTableSchema(_ tableName: String) throws -> String? {
        let sql = "SELECT sql FROM sqlite_master WHERE type='table' AND name=?;"
        return try queryScalar(sql, parameters: [tableName])
    }
}