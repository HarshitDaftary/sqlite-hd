import Foundation
import CustomSQLite

@main
struct CustomSQLiteExample {
    static func main() {
        print("🚀 CustomSQLite Example with SQLITE_ENABLE_QUEUE")
        print("================================================")
        
        // Create temporary database
        let tempDir = NSTemporaryDirectory()
        let dbPath = (tempDir as NSString).appendingPathComponent("example.db")
        
        do {
            let db = try CustomSQLite(path: dbPath)
            
            // Show SQLite and queue information
            let info = db.getDatabaseInfo()
            let queueInfo = db.getWriteQueueInfo()
            
            print("\n📊 Database Information:")
            print("SQLite Version: \(info["sqlite_version"] ?? "Unknown")")
            print("Write Queue Supported: \(queueInfo["supported"] ?? false)")
            print("Write Queue Enabled: \(db.isWriteQueueEnabled())")
            
            // Create example table
            try db.createTable("employees", columns: [
                "id INTEGER PRIMARY KEY AUTOINCREMENT",
                "name TEXT NOT NULL",
                "department TEXT",
                "salary REAL",
                "hired_date DATETIME DEFAULT CURRENT_TIMESTAMP"
            ])
            
            print("\n✅ Created 'employees' table")
            
            // Insert sample data
            let employees = [
                ["name": "Alice Johnson", "department": "Engineering", "salary": 85000.0],
                ["name": "Bob Smith", "department": "Marketing", "salary": 65000.0],
                ["name": "Charlie Brown", "department": "Engineering", "salary": 78000.0],
                ["name": "Diana Prince", "department": "HR", "salary": 72000.0]
            ]
            
            for employee in employees {
                try db.insert(into: "employees", values: employee)
            }
            
            print("✅ Inserted \(employees.count) employees")
            
            // Query and display data
            let allEmployees = try db.query("SELECT * FROM employees ORDER BY salary DESC;")
            
            print("\n👥 All Employees (by salary):")
            for employee in allEmployees {
                let name = employee["name"] as? String ?? "Unknown"
                let dept = employee["department"] as? String ?? "Unknown"
                let salary = employee["salary"] as? Double ?? 0
                print("  • \(name) - \(dept) - $\(Int(salary))")
            }
            
            // Demonstrate transaction
            print("\n💰 Giving Engineering team a raise...")
            try db.transaction {
                try db.execute(
                    "UPDATE employees SET salary = salary * 1.1 WHERE department = ?;",
                    parameters: ["Engineering"]
                )
            }
            
            // Query updated salaries
            let engineeringTeam = try db.query(
                "SELECT name, salary FROM employees WHERE department = ? ORDER BY name;",
                parameters: ["Engineering"]
            )
            
            print("Engineering team after raise:")
            for employee in engineeringTeam {
                let name = employee["name"] as? String ?? "Unknown"
                let salary = employee["salary"] as? Double ?? 0
                print("  • \(name) - $\(Int(salary))")
            }
            
            // Demonstrate concurrent writes
            print("\n🔄 Testing concurrent writes...")
            testConcurrentWrites(database: db)
            
            // Show final statistics
            let totalEmployees = try db.count(in: "employees")
            let avgSalary = try db.queryScalar("SELECT AVG(salary) FROM employees;")
            
            print("\n📈 Final Statistics:")
            print("Total Employees: \(totalEmployees)")
            if let avgSalaryStr = avgSalary, let avgSalaryNum = Double(avgSalaryStr) {
                print("Average Salary: $\(Int(avgSalaryNum))")
            }
            
            // Clean up
            db.closeDatabase()
            try? FileManager.default.removeItem(atPath: dbPath)
            
            print("\n🎉 Example completed successfully!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func testConcurrentWrites(database: CustomSQLite) {
        let dispatchGroup = DispatchGroup()
        let startTime = Date()
        
        // Create test table for concurrent writes
        try? database.createTable("concurrent_logs", columns: [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "thread_id INTEGER",
            "message TEXT",
            "timestamp DATETIME DEFAULT CURRENT_TIMESTAMP"
        ])
        
        var successCount = 0
        var errorCount = 0
        let lockQueue = DispatchQueue(label: "counter")
        
        // Launch 5 concurrent writers
        for threadId in 0..<5 {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .background).async {
                for messageId in 0..<10 {
                    do {
                        try database.insert(into: "concurrent_logs", values: [
                            "thread_id": threadId,
                            "message": "Log message \(messageId) from thread \(threadId)"
                        ])
                        
                        lockQueue.async { successCount += 1 }
                        
                    } catch {
                        lockQueue.async { errorCount += 1 }
                    }
                    
                    // Small delay to simulate real work
                    Thread.sleep(forTimeInterval: 0.01)
                }
                
                dispatchGroup.leave()
            }
        }
        
        // Wait for completion
        dispatchGroup.wait()
        
        let duration = Date().timeIntervalSince(startTime)
        let totalAttempts = 5 * 10
        let successRate = Double(successCount) / Double(totalAttempts) * 100
        
        print("Concurrent write test results:")
        print("  Duration: \(String(format: "%.2f", duration))s")
        print("  Successful writes: \(successCount)/\(totalAttempts)")
        print("  Success rate: \(String(format: "%.1f", successRate))%")
        print("  Errors: \(errorCount)")
        
        if successRate > 80 {
            print("  ✅ Excellent performance with write queue!")
        } else if successRate > 60 {
            print("  ⚠️  Good performance, write queue helping")
        } else {
            print("  ❌ Lower performance, check write queue support")
        }
    }
}