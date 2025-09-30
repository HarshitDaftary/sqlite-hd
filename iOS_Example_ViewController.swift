//
//  iOS Example App - ViewController.swift
//  Demonstrates custom SQLite with SQLITE_ENABLE_QUEUE in iOS
//

import UIKit

class ViewController: UIViewController {
    private var database: CustomSQLite?
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var messageCountLabel: UILabel!
    @IBOutlet weak var concurrentTestButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupDatabase()
        updateStatus()
    }
    
    private func setupUI() {
        statusLabel.text = "Initializing..."
        messageCountLabel.text = "Messages: 0"
        concurrentTestButton.setTitle("Test Concurrent Writes", for: .normal)
    }
    
    private func setupDatabase() {
        do {
            // Get database path in Documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                       in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("app.db").path
            
            // Initialize custom SQLite with queue support
            database = try CustomSQLite(path: dbPath)
            
            // Create tables
            try database?.createTable("messages", columns: [
                "id INTEGER PRIMARY KEY AUTOINCREMENT",
                "content TEXT NOT NULL",
                "thread_id INTEGER",
                "timestamp DATETIME DEFAULT CURRENT_TIMESTAMP"
            ])
            
            try database?.createTable("app_info", columns: [
                "key TEXT PRIMARY KEY",
                "value TEXT"
            ])
            
            // Store app info
            try database?.execute("INSERT OR REPLACE INTO app_info (key, value) VALUES (?, ?);", 
                                parameters: ["sqlite_version", getSQLiteVersion()])
            try database?.execute("INSERT OR REPLACE INTO app_info (key, value) VALUES (?, ?);", 
                                parameters: ["queue_enabled", database?.isWriteQueueEnabled() == true ? "YES" : "NO"])
            
            print("✅ Database initialized successfully")
            
        } catch {
            print("❌ Database setup failed: \(error)")
            statusLabel.text = "Database Error: \(error.localizedDescription)"
        }
    }
    
    private func getSQLiteVersion() -> String {
        do {
            return try database?.queryScalar("SELECT sqlite_version();") ?? "Unknown"
        } catch {
            return "Error"
        }
    }
    
    private func updateStatus() {
        guard let db = database else {
            statusLabel.text = "Database not initialized"
            return
        }
        
        do {
            let queueEnabled = db.isWriteQueueEnabled()
            let messageCount = try db.count(in: "messages")
            let sqliteVersion = getSQLiteVersion()
            
            DispatchQueue.main.async {
                self.statusLabel.text = "SQLite \(sqliteVersion) | Queue: \(queueEnabled ? "ON" : "OFF")"
                self.messageCountLabel.text = "Messages: \(messageCount)"
            }
            
        } catch {
            DispatchQueue.main.async {
                self.statusLabel.text = "Status Error: \(error.localizedDescription)"
            }
        }
    }
    
    @IBAction func testConcurrentWrites(_ sender: UIButton) {
        guard let db = database else { return }
        
        sender.isEnabled = false
        sender.setTitle("Testing...", for: .normal)
        
        // Clear previous test data
        do {
            try db.execute("DELETE FROM messages;")
        } catch {
            print("Error clearing messages: \(error)")
        }
        
        let startTime = Date()
        let dispatchGroup = DispatchGroup()
        
        // Launch 5 concurrent writer threads
        for threadId in 0..<5 {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .background).async {
                var successCount = 0
                var errorCount = 0
                
                for messageId in 0..<10 {
                    do {
                        try db.insert(into: "messages", values: [
                            "content": "Message \(messageId) from thread \(threadId)",
                            "thread_id": threadId
                        ])
                        successCount += 1
                        print("Thread \(threadId): wrote message \(messageId)")
                    } catch {
                        errorCount += 1
                        print("Thread \(threadId): error on message \(messageId): \(error)")
                    }
                    
                    // Small delay to simulate real-world conditions
                    Thread.sleep(forTimeInterval: 0.01)
                }
                
                print("Thread \(threadId) completed: \(successCount) successes, \(errorCount) errors")
                dispatchGroup.leave()
            }
        }
        
        // Wait for all threads to complete
        dispatchGroup.notify(queue: .main) {
            let duration = Date().timeIntervalSince(startTime)
            
            do {
                let totalMessages = try db.count(in: "messages")
                let expectedMessages = 5 * 10 // 5 threads × 10 messages each
                let successRate = Double(totalMessages) / Double(expectedMessages) * 100
                
                self.updateStatus()
                
                let alert = UIAlertController(
                    title: "Concurrent Write Test Complete",
                    message: """
                    Duration: \(String(format: "%.2f", duration))s
                    Messages Written: \(totalMessages)/\(expectedMessages)
                    Success Rate: \(String(format: "%.1f", successRate))%
                    
                    With SQLITE_ENABLE_QUEUE:
                    • Reduced lock contention
                    • Better concurrent performance
                    • Fewer retry loops needed
                    """,
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                
            } catch {
                let alert = UIAlertController(
                    title: "Test Error",
                    message: "Error counting results: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
            
            sender.isEnabled = true
            sender.setTitle("Test Concurrent Writes", for: .normal)
        }
    }
    
    @IBAction func showDatabaseInfo(_ sender: UIButton) {
        guard let db = database else { return }
        
        let info = db.getDatabaseInfo()
        let queueInfo = db.getWriteQueueInfo()
        
        var message = "Database Information:\n\n"
        message += "Path: \(info["path"] ?? "Unknown")\n"
        message += "SQLite Version: \(info["sqlite_version"] ?? "Unknown")\n"
        message += "File Size: \(info["file_size"] ?? 0) bytes\n\n"
        message += "Write Queue Info:\n"
        message += "Supported: \(queueInfo["supported"] ?? false)\n"
        message += "Enabled: \(queueInfo["enabled"] ?? false)\n"
        
        if let error = queueInfo["error"] as? String {
            message += "Error: \(error)\n"
        }
        
        do {
            let tables = try db.getTableNames()
            message += "\nTables: \(tables.joined(separator: ", "))"
        } catch {
            message += "\nError getting tables: \(error.localizedDescription)"
        }
        
        let alert = UIAlertController(
            title: "Database Info",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @IBAction func toggleWriteQueue(_ sender: UIButton) {
        guard let db = database else { return }
        
        do {
            let currentlyEnabled = db.isWriteQueueEnabled()
            try db.setWriteQueueEnabled(!currentlyEnabled)
            
            updateStatus()
            
            let newStatus = db.isWriteQueueEnabled() ? "enabled" : "disabled"
            let alert = UIAlertController(
                title: "Write Queue Toggled",
                message: "Write queue is now \(newStatus)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            
        } catch {
            let alert = UIAlertController(
                title: "Toggle Error",
                message: "Failed to toggle write queue: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

// MARK: - Additional Demo Methods

extension ViewController {
    
    private func demoTransactions() {
        guard let db = database else { return }
        
        do {
            // Demonstrate atomic transactions
            try db.transaction {
                try db.insert(into: "messages", values: [
                    "content": "Transaction message 1",
                    "thread_id": 999
                ])
                
                try db.insert(into: "messages", values: [
                    "content": "Transaction message 2", 
                    "thread_id": 999
                ])
                
                // Both inserts succeed together or both fail together
            }
            
            print("✅ Transaction completed successfully")
            
        } catch {
            print("❌ Transaction failed: \(error)")
        }
    }
    
    private func demoQueryMethods() {
        guard let db = database else { return }
        
        do {
            // Query all messages
            let allMessages = try db.query("SELECT * FROM messages ORDER BY id DESC LIMIT 5;")
            print("Recent messages: \(allMessages)")
            
            // Query with parameters
            let threadMessages = try db.query("SELECT * FROM messages WHERE thread_id = ?;", 
                                            parameters: [1])
            print("Thread 1 messages: \(threadMessages)")
            
            // Scalar query
            let totalCount = try db.queryScalar("SELECT COUNT(*) FROM messages;")
            print("Total message count: \(totalCount ?? "0")")
            
            // Count helper
            let countByHelper = try db.count(in: "messages", where: "thread_id > ?", parameters: [0])
            print("Messages with thread_id > 0: \(countByHelper)")
            
        } catch {
            print("❌ Query demo failed: \(error)")
        }
    }
}