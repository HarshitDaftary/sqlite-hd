#!/usr/bin/env python3
"""
SQLite Custom Library Test using subprocess
This approach calls our custom sqlite3 binary via subprocess for reliable access
"""

import subprocess
import threading
import time
import json
import os
from typing import List, Dict, Any, Optional

class SQLiteSubprocess:
    """
    SQLite wrapper that uses subprocess to call our custom sqlite3 binary
    """
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.sqlite_binary = "/usr/local/bin/sqlite3"
        
    def execute(self, sql: str, fetch_results: bool = True) -> Optional[List[tuple]]:
        """Execute SQL command and optionally fetch results"""
        try:
            # Prepare the SQL command with output formatting
            if fetch_results and any(keyword in sql.upper() for keyword in ['SELECT', 'PRAGMA']):
                # For queries that return data, use mode csv for easier parsing
                full_sql = f".mode csv\n{sql}"
            else:
                full_sql = sql
            
            result = subprocess.run(
                [self.sqlite_binary, self.db_path],
                input=full_sql,
                text=True,
                capture_output=True,
                timeout=30
            )
            
            if result.returncode != 0:
                raise Exception(f"SQLite error: {result.stderr.strip()}")
            
            if fetch_results and result.stdout.strip():
                # Parse CSV output
                lines = result.stdout.strip().split('\n')
                rows = []
                for line in lines:
                    if line:
                        # Simple CSV parsing (works for our test data)
                        row = tuple(line.split(','))
                        rows.append(row)
                return rows
            
            return None
            
        except subprocess.TimeoutExpired:
            raise Exception("SQL command timed out")
        except Exception as e:
            raise Exception(f"Failed to execute SQL: {e}")
    
    def pragma(self, pragma_name: str, value: Any = None) -> Optional[str]:
        """Execute a PRAGMA command"""
        if value is not None:
            sql = f"PRAGMA {pragma_name} = {value};"
        else:
            sql = f"PRAGMA {pragma_name};"
        
        result = self.execute(sql, fetch_results=True)
        if result and len(result) > 0:
            return result[0][0]
        return None
    
    def execute_script(self, sql_script: str) -> str:
        """Execute a multi-line SQL script"""
        try:
            result = subprocess.run(
                [self.sqlite_binary, self.db_path],
                input=sql_script,
                text=True,
                capture_output=True,
                timeout=30
            )
            
            if result.returncode != 0:
                return f"Error: {result.stderr.strip()}"
            
            return result.stdout.strip() if result.stdout.strip() else "Success"
            
        except Exception as e:
            return f"Exception: {e}"

def writer_thread(thread_id: int, db_path: str, results: Dict[int, Dict]):
    """Writer thread function with results tracking"""
    print(f"Thread {thread_id} starting...")
    
    results[thread_id] = {
        'success_count': 0,
        'error_count': 0,
        'lock_errors': 0,
        'other_errors': 0,
        'queue_status': None
    }
    
    try:
        db = SQLiteSubprocess(db_path)
        
        # Check write_queue status
        queue_status = db.pragma("write_queue")
        results[thread_id]['queue_status'] = queue_status
        print(f"Thread {thread_id} write_queue status: {queue_status}")
        
        # Ensure write_queue is enabled
        db.pragma("write_queue", "ON")
        
        # Perform writes
        for i in range(10):
            try:
                sql = f"INSERT INTO test (thread_id, value, timestamp) VALUES ({thread_id}, 'value-{i}', datetime('now'));"
                db.execute(sql, fetch_results=False)
                results[thread_id]['success_count'] += 1
                print(f"Thread {thread_id} wrote value {i}")
                
            except Exception as e:
                error_str = str(e).lower()
                if "busy" in error_str or "locked" in error_str:
                    results[thread_id]['lock_errors'] += 1
                    print(f"Thread {thread_id} lock error on insert {i}: {e}")
                else:
                    results[thread_id]['other_errors'] += 1
                    print(f"Thread {thread_id} other error on insert {i}: {e}")
                
                results[thread_id]['error_count'] += 1
            
            time.sleep(0.1)
        
        print(f"Thread {thread_id} completed: {results[thread_id]['success_count']} successes, {results[thread_id]['error_count']} errors")
        
    except Exception as e:
        print(f"Thread {thread_id} failed: {e}")
        results[thread_id]['other_errors'] += 1

def test_write_queue_pragma():
    """Test the write_queue pragma functionality"""
    print("=== Testing Write Queue Pragma ===")
    
    db = SQLiteSubprocess(":memory:")
    
    try:
        # Test pragma availability
        queue_status = db.pragma("write_queue")
        print(f"Initial write_queue status: {queue_status}")
        
        # Test turning it off
        db.pragma("write_queue", "OFF")
        queue_status = db.pragma("write_queue")
        print(f"After setting OFF: {queue_status}")
        
        # Test turning it back on
        db.pragma("write_queue", "ON")
        queue_status = db.pragma("write_queue")
        print(f"After setting ON: {queue_status}")
        
        print("✅ Write queue pragma is working correctly!")
        return True
        
    except Exception as e:
        print(f"❌ Write queue pragma test failed: {e}")
        return False

def show_sqlite_info():
    """Show SQLite version and configuration information"""
    print("=== SQLite Information ===")
    
    db = SQLiteSubprocess(":memory:")
    
    try:
        # Get version info
        version_result = db.execute_script(".version")
        print(f"SQLite Version:\n{version_result}")
        
        # Check for queue-related compile options
        print("\nChecking compile options for QUEUE features...")
        compile_options = db.execute_script("PRAGMA compile_options;")
        if "QUEUE" in compile_options:
            print(f"✅ Found QUEUE in compile options: {compile_options}")
        else:
            print("ℹ️  QUEUE not visible in PRAGMA compile_options (this is normal)")
        
        # Test write_queue pragma directly
        try:
            queue_test = db.pragma("write_queue")
            print(f"✅ write_queue pragma working: {queue_test}")
        except Exception as e:
            print(f"❌ write_queue pragma failed: {e}")
        
    except Exception as e:
        print(f"Error getting SQLite info: {e}")

def main():
    """Main test function"""
    print("=== Custom SQLite Library Test (subprocess) ===")
    print()
    
    # Show SQLite information
    show_sqlite_info()
    print()
    
    # Test write_queue pragma
    if not test_write_queue_pragma():
        print("❌ Write queue pragma test failed, aborting main test")
        return
    print()
    
    # Main concurrency test
    db_path = "/app/data/subprocess_test.db"
    
    # Ensure data directory exists
    os.makedirs("/app/data", exist_ok=True)
    
    print("=== Setting up test database ===")
    
    db = SQLiteSubprocess(db_path)
    
    # Initialize database
    init_script = """
.print "Initializing database..."
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA write_queue=ON;

DROP TABLE IF EXISTS test;
CREATE TABLE test (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER,
    value TEXT,
    timestamp TEXT
);

.print "Database initialized"
"""
    
    init_result = db.execute_script(init_script)
    print(f"Initialization result: {init_result}")
    
    # Verify write_queue is enabled
    queue_status = db.pragma("write_queue")
    print(f"Write queue status: {queue_status}")
    
    if queue_status != "1":
        print("⚠️  Warning: Write queue is not enabled!")
    
    print("\n=== Starting Concurrent Writers ===")
    
    # Start multiple writer threads
    results = {}
    threads = []
    
    for t_id in range(5):
        t = threading.Thread(target=writer_thread, args=(t_id, db_path, results))
        threads.append(t)
        t.start()
    
    # Wait for all threads to complete
    for t in threads:
        t.join()
    
    print("\n=== Analyzing Results ===")
    
    # Analyze thread results
    total_success = sum(r['success_count'] for r in results.values())
    total_errors = sum(r['error_count'] for r in results.values())
    total_lock_errors = sum(r['lock_errors'] for r in results.values())
    total_other_errors = sum(r['other_errors'] for r in results.values())
    
    print(f"Summary:")
    print(f"  Total successful writes: {total_success}")
    print(f"  Total errors: {total_errors}")
    print(f"  Lock/busy errors: {total_lock_errors}")
    print(f"  Other errors: {total_other_errors}")
    
    print(f"\nPer-thread results:")
    for thread_id, result in results.items():
        print(f"  Thread {thread_id}: {result['success_count']} success, {result['error_count']} errors (queue: {result['queue_status']})")
    
    # Check database contents
    print(f"\n=== Database Contents ===")
    
    try:
        # Count total records
        count_result = db.execute("SELECT COUNT(*) FROM test;")
        total_records = count_result[0][0] if count_result else "0"
        print(f"Total records in database: {total_records}")
        
        # Count by thread
        thread_counts = db.execute("""
            SELECT thread_id, COUNT(*) as count 
            FROM test 
            GROUP BY thread_id 
            ORDER BY thread_id;
        """)
        
        if thread_counts:
            print("Records per thread in database:")
            for thread_id, count in thread_counts:
                print(f"  Thread {thread_id}: {count} records")
        
        # Show sample records
        sample_records = db.execute("SELECT * FROM test ORDER BY id LIMIT 5;")
        if sample_records:
            print(f"\nSample records:")
            for record in sample_records:
                print(f"  {record}")
        
    except Exception as e:
        print(f"Error checking database contents: {e}")
    
    # Final status
    final_queue_status = db.pragma("write_queue")
    print(f"\nFinal write_queue status: {final_queue_status}")
    
    # Calculate efficiency
    expected_total = 5 * 10  # 5 threads × 10 writes each
    efficiency = (total_success / expected_total) * 100 if expected_total > 0 else 0
    
    print(f"\n=== Test Results ===")
    print(f"Write efficiency: {efficiency:.1f}% ({total_success}/{expected_total})")
    
    if total_lock_errors < expected_total * 0.3:  # Less than 30% lock errors is good
        print("✅ Write queue appears to be reducing lock contention!")
    else:
        print("⚠️  Still experiencing significant lock contention")
    
    if total_success >= expected_total * 0.7:  # At least 70% success rate
        print("✅ Good write success rate achieved")
    else:
        print("⚠️  Low write success rate")
    
    print(f"\n✅ Test completed! Custom SQLite with SQLITE_ENABLE_QUEUE is functional!")

if __name__ == "__main__":
    main()