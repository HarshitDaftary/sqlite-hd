import subprocess
import os
import threading
import time

def run_sqlite_command(db_path, sql_command):
    """Run a SQLite command using our custom sqlite3 binary"""
    try:
        result = subprocess.run(
            ['sqlite3', db_path], 
            input=sql_command,
            text=True,
            capture_output=True,
            timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            return f"Error: {result.stderr.strip()}"
    except Exception as e:
        return f"Exception: {e}"

def writer(thread_id, db_path):
    """Writer function using subprocess calls to custom SQLite"""
    print(f"Thread {thread_id} starting...")
    
    # Check write_queue status for this thread
    queue_status = run_sqlite_command(db_path, "PRAGMA write_queue;")
    print(f"Thread {thread_id} write_queue status: {queue_status}")
    
    # Enable write_queue for this thread's operations
    run_sqlite_command(db_path, "PRAGMA write_queue = ON;")
    
    for i in range(10):
        sql = f"INSERT INTO test (value) VALUES ('thread-{thread_id}-val-{i}');"
        result = run_sqlite_command(db_path, sql)
        if "Error" in result or "Exception" in result:
            print(f"Thread {thread_id} error on insert {i}: {result}")
        else:
            print(f"Thread {thread_id} wrote value {i}")
        time.sleep(0.1)
    
    print(f"Thread {thread_id} completed")

def main():
    db_path = "/app/data/custom_sqlite_test.db"
    
    # Initialize the database
    print("Initializing database...")
    
    init_sql = """
    PRAGMA journal_mode=WAL;
    PRAGMA busy_timeout=5000;
    PRAGMA write_queue=ON;
    CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, value TEXT);
    DELETE FROM test;
    """
    
    result = run_sqlite_command(db_path, init_sql)
    print(f"Database initialization result: {result}")
    
    # Check if write_queue is available
    queue_check = run_sqlite_command(db_path, "PRAGMA write_queue;")
    print(f"Write queue status: {queue_check}")
    
    # Show SQLite version and compile options
    version_info = run_sqlite_command(db_path, ".version")
    print(f"SQLite version: {version_info}")
    
    print("\nStarting concurrent writers...")
    
    # Start multiple writer threads
    threads = []
    for t_id in range(5):
        t = threading.Thread(target=writer, args=(t_id, db_path))
        threads.append(t)
        t.start()
    
    # Wait for all threads to complete
    for t in threads:
        t.join()
    
    print("\nAll threads completed. Checking results...")
    
    # Count total records
    count_result = run_sqlite_command(db_path, "SELECT COUNT(*) FROM test;")
    print(f"Total records: {count_result}")
    
    # Show all records
    all_records = run_sqlite_command(db_path, "SELECT * FROM test ORDER BY id;")
    print(f"All records:\n{all_records}")
    
    # Final write queue status
    final_queue_status = run_sqlite_command(db_path, "PRAGMA write_queue;")
    print(f"Final write_queue status: {final_queue_status}")

if __name__ == "__main__":
    main()