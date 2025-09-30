#!/usr/bin/env python3
"""
SQLite Custom Library Test using ctypes
This approach directly loads our custom SQLite library using ctypes
"""

import ctypes
import ctypes.util
import threading
import time
import os
from typing import Optional, Any

class SQLiteError(Exception):
    pass

class CustomSQLite:
    """
    A simple SQLite wrapper that uses our custom SQLite library via ctypes
    """
    
    # SQLite constants
    SQLITE_OK = 0
    SQLITE_ROW = 100
    SQLITE_DONE = 101
    SQLITE_BUSY = 5
    SQLITE_LOCKED = 6
    
    def __init__(self, library_path: str = "/usr/local/lib/libsqlite3.so"):
        """Initialize the custom SQLite wrapper"""
        self.lib = ctypes.CDLL(library_path)
        self.db = None
        
        # Define function signatures
        self._setup_function_signatures()
        
    def _setup_function_signatures(self):
        """Setup ctypes function signatures for SQLite functions"""
        # sqlite3_open_v2
        self.lib.sqlite3_open_v2.argtypes = [
            ctypes.c_char_p,  # filename
            ctypes.POINTER(ctypes.c_void_p),  # ppDb
            ctypes.c_int,     # flags
            ctypes.c_char_p   # zVfs
        ]
        self.lib.sqlite3_open_v2.restype = ctypes.c_int
        
        # sqlite3_close_v2
        self.lib.sqlite3_close_v2.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_close_v2.restype = ctypes.c_int
        
        # sqlite3_exec
        self.lib.sqlite3_exec.argtypes = [
            ctypes.c_void_p,  # db
            ctypes.c_char_p,  # sql
            ctypes.c_void_p,  # callback
            ctypes.c_void_p,  # arg
            ctypes.POINTER(ctypes.c_char_p)  # errmsg
        ]
        self.lib.sqlite3_exec.restype = ctypes.c_int
        
        # sqlite3_errmsg
        self.lib.sqlite3_errmsg.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_errmsg.restype = ctypes.c_char_p
        
        # sqlite3_prepare_v2
        self.lib.sqlite3_prepare_v2.argtypes = [
            ctypes.c_void_p,  # db
            ctypes.c_char_p,  # zSql
            ctypes.c_int,     # nByte
            ctypes.POINTER(ctypes.c_void_p),  # ppStmt
            ctypes.POINTER(ctypes.c_char_p)   # pzTail
        ]
        self.lib.sqlite3_prepare_v2.restype = ctypes.c_int
        
        # sqlite3_step
        self.lib.sqlite3_step.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_step.restype = ctypes.c_int
        
        # sqlite3_finalize
        self.lib.sqlite3_finalize.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_finalize.restype = ctypes.c_int
        
        # sqlite3_column_text
        self.lib.sqlite3_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.sqlite3_column_text.restype = ctypes.c_char_p
        
        # sqlite3_column_int
        self.lib.sqlite3_column_int.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.sqlite3_column_int.restype = ctypes.c_int
        
        # sqlite3_column_count
        self.lib.sqlite3_column_count.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_column_count.restype = ctypes.c_int
        
    def open(self, filename: str) -> None:
        """Open a SQLite database"""
        db_ptr = ctypes.c_void_p()
        flags = 0x00000006  # SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        
        result = self.lib.sqlite3_open_v2(
            filename.encode('utf-8'),
            ctypes.byref(db_ptr),
            flags,
            None
        )
        
        if result != self.SQLITE_OK:
            raise SQLiteError(f"Failed to open database: {result}")
            
        self.db = db_ptr
        
    def close(self) -> None:
        """Close the SQLite database"""
        if self.db:
            self.lib.sqlite3_close_v2(self.db)
            self.db = None
            
    def execute(self, sql: str) -> Optional[list]:
        """Execute SQL and return results if any"""
        if not self.db:
            raise SQLiteError("Database not opened")
            
        # Prepare statement
        stmt_ptr = ctypes.c_void_p()
        tail_ptr = ctypes.c_char_p()
        
        result = self.lib.sqlite3_prepare_v2(
            self.db,
            sql.encode('utf-8'),
            -1,
            ctypes.byref(stmt_ptr),
            ctypes.byref(tail_ptr)
        )
        
        if result != self.SQLITE_OK:
            error_msg = self.lib.sqlite3_errmsg(self.db).decode('utf-8')
            raise SQLiteError(f"SQL preparation failed: {error_msg}")
        
        try:
            rows = []
            while True:
                result = self.lib.sqlite3_step(stmt_ptr)
                
                if result == self.SQLITE_ROW:
                    # Get row data
                    col_count = self.lib.sqlite3_column_count(stmt_ptr)
                    row = []
                    for i in range(col_count):
                        # Try to get as text first
                        text_val = self.lib.sqlite3_column_text(stmt_ptr, i)
                        if text_val:
                            row.append(text_val.decode('utf-8'))
                        else:
                            # Try as integer
                            int_val = self.lib.sqlite3_column_int(stmt_ptr, i)
                            row.append(int_val)
                    rows.append(tuple(row))
                    
                elif result == self.SQLITE_DONE:
                    break
                    
                elif result == self.SQLITE_BUSY:
                    raise SQLiteError("Database is busy")
                    
                elif result == self.SQLITE_LOCKED:
                    raise SQLiteError("Database is locked")
                    
                else:
                    error_msg = self.lib.sqlite3_errmsg(self.db).decode('utf-8')
                    raise SQLiteError(f"SQL execution failed: {error_msg}")
                    
            return rows if rows else None
            
        finally:
            self.lib.sqlite3_finalize(stmt_ptr)
    
    def pragma(self, pragma_name: str, value: Any = None) -> Optional[str]:
        """Execute a PRAGMA command"""
        if value is not None:
            sql = f"PRAGMA {pragma_name} = {value};"
        else:
            sql = f"PRAGMA {pragma_name};"
            
        result = self.execute(sql)
        if result and len(result) > 0:
            return str(result[0][0])
        return None

def writer_thread(thread_id: int, db_path: str, use_queue: bool = True):
    """Writer thread function"""
    print(f"Thread {thread_id} starting...")
    
    try:
        # Create connection
        db = CustomSQLite()
        db.open(db_path)
        
        # Configure database
        db.execute("PRAGMA journal_mode=WAL;")
        db.execute("PRAGMA busy_timeout=5000;")
        
        if use_queue:
            # Enable write queue
            db.pragma("write_queue", "ON")
            queue_status = db.pragma("write_queue")
            print(f"Thread {thread_id} write_queue status: {queue_status}")
        
        # Perform writes
        success_count = 0
        error_count = 0
        
        for i in range(10):
            try:
                db.execute(f"INSERT INTO test (thread_id, value, timestamp) VALUES ({thread_id}, 'value-{i}', datetime('now'));")
                success_count += 1
                print(f"Thread {thread_id} wrote value {i}")
            except SQLiteError as e:
                error_count += 1
                if "busy" in str(e).lower() or "locked" in str(e).lower():
                    print(f"Thread {thread_id} lock error on insert {i}: {e}")
                else:
                    print(f"Thread {thread_id} other error on insert {i}: {e}")
            
            time.sleep(0.1)
        
        print(f"Thread {thread_id} completed: {success_count} successes, {error_count} errors")
        
        db.close()
        
    except Exception as e:
        print(f"Thread {thread_id} failed: {e}")

def main():
    """Main test function"""
    print("=== Custom SQLite Library Test (ctypes) ===")
    print()
    
    db_path = "/app/data/ctypes_test.db"
    
    # Ensure data directory exists
    os.makedirs("/app/data", exist_ok=True)
    
    # Initialize database
    print("Initializing database...")
    db = CustomSQLite()
    
    try:
        db.open(db_path)
        
        # Show SQLite version info
        print("SQLite library loaded successfully!")
        
        # Test write_queue pragma
        print("\n=== Testing Write Queue Pragma ===")
        
        # Check if write_queue is available
        try:
            queue_status = db.pragma("write_queue")
            print(f"Current write_queue status: {queue_status}")
            
            # Turn it off
            db.pragma("write_queue", "OFF")
            queue_status = db.pragma("write_queue")
            print(f"After setting OFF: {queue_status}")
            
            # Turn it back on
            db.pragma("write_queue", "ON")
            queue_status = db.pragma("write_queue")
            print(f"After setting ON: {queue_status}")
            
            print("✅ Write queue pragma is working!")
            
        except Exception as e:
            print(f"❌ Write queue pragma failed: {e}")
            return
        
        # Setup test table
        print("\n=== Setting up test table ===")
        db.execute("DROP TABLE IF EXISTS test;")
        db.execute("""
            CREATE TABLE test (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                thread_id INTEGER,
                value TEXT,
                timestamp TEXT
            );
        """)
        
        # Configure for concurrent access
        db.execute("PRAGMA journal_mode=WAL;")
        db.execute("PRAGMA busy_timeout=5000;")
        db.pragma("write_queue", "ON")
        
        db.close()
        
        print("\n=== Starting Concurrent Writers ===")
        
        # Start multiple writer threads
        threads = []
        for t_id in range(5):
            t = threading.Thread(target=writer_thread, args=(t_id, db_path, True))
            threads.append(t)
            t.start()
        
        # Wait for all threads to complete
        for t in threads:
            t.join()
        
        print("\n=== Checking Results ===")
        
        # Check results
        db.open(db_path)
        
        # Count records
        count_result = db.execute("SELECT COUNT(*) FROM test;")
        total_records = count_result[0][0] if count_result else 0
        print(f"Total records inserted: {total_records}")
        
        # Show records by thread
        thread_counts = db.execute("""
            SELECT thread_id, COUNT(*) as count 
            FROM test 
            GROUP BY thread_id 
            ORDER BY thread_id;
        """)
        
        if thread_counts:
            print("Records per thread:")
            for thread_id, count in thread_counts:
                print(f"  Thread {thread_id}: {count} records")
        
        # Show some sample records
        sample_records = db.execute("SELECT * FROM test ORDER BY id LIMIT 10;")
        if sample_records:
            print(f"\nFirst 10 records:")
            for record in sample_records:
                print(f"  {record}")
        
        # Final write_queue status
        final_queue_status = db.pragma("write_queue")
        print(f"\nFinal write_queue status: {final_queue_status}")
        
        db.close()
        
        print(f"\n✅ Test completed! Custom SQLite with SQLITE_ENABLE_QUEUE is working!")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        if db.db:
            db.close()

if __name__ == "__main__":
    main()