#!/usr/bin/env python3
"""
SQLite Custom Library Test using native Python sqlite3 with library replacement
This approach tries to use the standard sqlite3 module but with our custom library
"""

import sqlite3
import threading
import time
import os
import ctypes
from typing import Dict, Any

def preload_custom_sqlite():
    """Preload our custom SQLite library"""
    try:
        # Try to preload our custom library
        custom_lib = ctypes.CDLL("/usr/local/lib/libsqlite3.so", mode=ctypes.RTLD_GLOBAL)
        print("✅ Custom SQLite library preloaded")
        return True
    except Exception as e:
        print(f"⚠️  Could not preload custom SQLite library: {e}")
        return False

def test_sqlite_capabilities():
    """Test what SQLite capabilities are available"""
    print("=== Testing SQLite Capabilities ===")
    
    # Check SQLite version
    print(f"Python sqlite3 module SQLite version: {sqlite3.sqlite_version}")
    print(f"Python sqlite3 module version: {sqlite3.version}")
    
    # Test connection
    try:
        conn = sqlite3.connect(":memory:")
        cursor = conn.cursor()
        
        # Test write_queue pragma
        try:
            cursor.execute("PRAGMA write_queue;")
            result = cursor.fetchone()
            if result:
                print(f"✅ write_queue pragma available: {result[0]}")
                
                # Test setting it
                cursor.execute("PRAGMA write_queue = OFF;")
                cursor.execute("PRAGMA write_queue;")
                result = cursor.fetchone()
                print(f"After setting OFF: {result[0]}")
                
                cursor.execute("PRAGMA write_queue = ON;")
                cursor.execute("PRAGMA write_queue;")
                result = cursor.fetchone()
                print(f"After setting ON: {result[0]}")
                
                return True
            else:
                print("❌ write_queue pragma returned no result")
                return False
                
        except sqlite3.OperationalError as e:
            print(f"❌ write_queue pragma not available: {e}")
            return False
        finally:
            conn.close()
            
    except Exception as e:
        print(f"❌ Failed to test SQLite capabilities: {e}")
        return False

def writer_thread(thread_id: int, db_path: str, results: Dict[int, Dict]):
    """Writer thread function"""
    print(f"Thread {thread_id} starting...")
    
    results[thread_id] = {
        'success_count': 0,
        'error_count': 0,
        'lock_errors': 0,
        'busy_errors': 0,
        'other_errors': 0
    }
    
    try:
        conn = sqlite3.connect(db_path, timeout=30.0)
        cursor = conn.cursor()
        
        # Enable write_queue if available
        try:
            cursor.execute("PRAGMA write_queue = ON;")
            cursor.execute("PRAGMA write_queue;")
            queue_status = cursor.fetchone()
            print(f"Thread {thread_id} write_queue status: {queue_status[0] if queue_status else 'N/A'}")
        except:
            pass  # Ignore if not available
        
        # Perform writes
        for i in range(10):
            try:
                cursor.execute(
                    "INSERT INTO test (thread_id, value, timestamp) VALUES (?, ?, datetime('now'));",
                    (thread_id, f'value-{i}')
                )
                conn.commit()
                results[thread_id]['success_count'] += 1
                print(f"Thread {thread_id} wrote value {i}")
                
            except sqlite3.OperationalError as e:
                error_str = str(e).lower()
                if "database is locked" in error_str:
                    results[thread_id]['lock_errors'] += 1
                    print(f"Thread {thread_id} locked on insert {i}")
                elif "database is busy" in error_str:
                    results[thread_id]['busy_errors'] += 1
                    print(f"Thread {thread_id} busy on insert {i}")
                else:
                    results[thread_id]['other_errors'] += 1
                    print(f"Thread {thread_id} error on insert {i}: {e}")
                
                results[thread_id]['error_count'] += 1
                
            except Exception as e:
                results[thread_id]['other_errors'] += 1
                results[thread_id]['error_count'] += 1
                print(f"Thread {thread_id} unexpected error on insert {i}: {e}")
            
            time.sleep(0.1)
        
        conn.close()
        print(f"Thread {thread_id} completed: {results[thread_id]['success_count']} successes, {results[thread_id]['error_count']} errors")
        
    except Exception as e:
        print(f"Thread {thread_id} failed to start: {e}")
        results[thread_id]['other_errors'] += 1

def main():
    """Main test function"""
    print("=== Custom SQLite Library Test (native python) ===")
    print()
    
    # Try to preload custom library
    preload_custom_sqlite()
    print()
    
    # Test SQLite capabilities
    if not test_sqlite_capabilities():
        print("❌ SQLite capabilities test failed")
        print("ℹ️  This suggests the Python sqlite3 module is not using our custom library")
        print("ℹ️  This is expected - Python often has its own compiled-in SQLite")
        return
    
    print("✅ SQLite capabilities test passed!")
    print()
    
    # Main concurrency test
    db_path = "/app/data/native_test.db"
    
    # Ensure data directory exists
    os.makedirs("/app/data", exist_ok=True)
    
    print("=== Setting up test database ===")
    
    # Initialize database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Setup database
    cursor.execute("PRAGMA journal_mode=WAL;")
    cursor.execute("PRAGMA busy_timeout=5000;")
    
    # Try to enable write_queue
    try:
        cursor.execute("PRAGMA write_queue=ON;")
        cursor.execute("PRAGMA write_queue;")
        queue_status = cursor.fetchone()
        print(f"Write queue status: {queue_status[0] if queue_status else 'Not available'}")
    except:
        print("Write queue not available in this build")
    
    # Create test table
    cursor.execute("DROP TABLE IF EXISTS test;")
    cursor.execute("""
        CREATE TABLE test (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            thread_id INTEGER,
            value TEXT,
            timestamp TEXT
        );
    """)
    
    conn.commit()
    conn.close()
    
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
    
    # Analyze results
    total_success = sum(r['success_count'] for r in results.values())
    total_errors = sum(r['error_count'] for r in results.values())
    total_lock_errors = sum(r['lock_errors'] for r in results.values())
    total_busy_errors = sum(r['busy_errors'] for r in results.values())
    total_other_errors = sum(r['other_errors'] for r in results.values())
    
    print(f"Summary:")
    print(f"  Total successful writes: {total_success}")
    print(f"  Total errors: {total_errors}")
    print(f"  Lock errors: {total_lock_errors}")
    print(f"  Busy errors: {total_busy_errors}")
    print(f"  Other errors: {total_other_errors}")
    
    print(f"\nPer-thread results:")
    for thread_id, result in results.items():
        print(f"  Thread {thread_id}: {result['success_count']} success, {result['error_count']} errors")
    
    # Check database contents
    print(f"\n=== Database Contents ===")
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Count total records
    cursor.execute("SELECT COUNT(*) FROM test;")
    total_records = cursor.fetchone()[0]
    print(f"Total records in database: {total_records}")
    
    # Count by thread
    cursor.execute("""
        SELECT thread_id, COUNT(*) as count 
        FROM test 
        GROUP BY thread_id 
        ORDER BY thread_id;
    """)
    thread_counts = cursor.fetchall()
    
    if thread_counts:
        print("Records per thread in database:")
        for thread_id, count in thread_counts:
            print(f"  Thread {thread_id}: {count} records")
    
    # Show sample records
    cursor.execute("SELECT * FROM test ORDER BY id LIMIT 5;")
    sample_records = cursor.fetchall()
    if sample_records:
        print(f"\nSample records:")
        for record in sample_records:
            print(f"  {record}")
    
    conn.close()
    
    # Calculate efficiency
    expected_total = 5 * 10  # 5 threads × 10 writes each
    efficiency = (total_success / expected_total) * 100 if expected_total > 0 else 0
    
    print(f"\n=== Test Results ===")
    print(f"Write efficiency: {efficiency:.1f}% ({total_success}/{expected_total})")
    
    if total_lock_errors + total_busy_errors < expected_total * 0.3:
        print("✅ Low lock contention achieved!")
    else:
        print("⚠️  Significant lock contention observed")
    
    print(f"\n✅ Test completed!")

if __name__ == "__main__":
    main()