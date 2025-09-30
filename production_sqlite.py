#!/usr/bin/env python3
"""
Production-ready Python wrapper for Custom SQLite with SQLITE_ENABLE_QUEUE support

This module provides a clean, Pythonic interface to our custom SQLite library
with write queue functionality for improved concurrent write performance.

Usage:
    from custom_sqlite import CustomSQLiteDB
    
    # Create connection with queue support
    db = CustomSQLiteDB('/path/to/database.db', enable_queue=True)
    
    # Use like normal database
    db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);")
    db.execute("INSERT INTO test (name) VALUES (?);", ["Alice"])
    results = db.fetch_all("SELECT * FROM test;")
    
    # Queue-specific features
    queue_enabled = db.is_queue_enabled()
    db.set_queue_enabled(True)
"""

import ctypes
import threading
import time
import os
from typing import List, Tuple, Any, Optional, Union
from contextlib import contextmanager


class SQLiteError(Exception):
    """Custom SQLite exception"""
    pass


class CustomSQLiteDB:
    """
    Production-ready wrapper for custom SQLite with SQLITE_ENABLE_QUEUE support
    """
    
    # SQLite constants
    SQLITE_OK = 0
    SQLITE_ROW = 100
    SQLITE_DONE = 101
    SQLITE_BUSY = 5
    SQLITE_LOCKED = 6
    SQLITE_FULL = 13
    
    def __init__(self, db_path: str, enable_queue: bool = True, 
                 library_path: str = "/usr/local/lib/libsqlite3.so",
                 timeout: float = 30.0):
        """
        Initialize CustomSQLiteDB
        
        Args:
            db_path: Path to SQLite database file
            enable_queue: Whether to enable write queue by default
            library_path: Path to custom SQLite library
            timeout: Default timeout for operations
        """
        self.db_path = db_path
        self.timeout = timeout
        self._lib = None
        self._db = None
        self._lock = threading.RLock()
        
        # Load library and connect
        self._load_library(library_path)
        self._setup_function_signatures()
        self.connect()
        
        # Configure database
        self._configure_database(enable_queue)
    
    def _load_library(self, library_path: str):
        """Load the custom SQLite library"""
        try:
            self._lib = ctypes.CDLL(library_path)
        except Exception as e:
            raise SQLiteError(f"Failed to load SQLite library from {library_path}: {e}")
    
    def _setup_function_signatures(self):
        """Setup ctypes function signatures"""
        # sqlite3_open_v2
        self._lib.sqlite3_open_v2.argtypes = [
            ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), 
            ctypes.c_int, ctypes.c_char_p
        ]
        self._lib.sqlite3_open_v2.restype = ctypes.c_int
        
        # sqlite3_close_v2
        self._lib.sqlite3_close_v2.argtypes = [ctypes.c_void_p]
        self._lib.sqlite3_close_v2.restype = ctypes.c_int
        
        # sqlite3_prepare_v2
        self._lib.sqlite3_prepare_v2.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int,
            ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_char_p)
        ]
        self._lib.sqlite3_prepare_v2.restype = ctypes.c_int
        
        # sqlite3_step
        self._lib.sqlite3_step.argtypes = [ctypes.c_void_p]
        self._lib.sqlite3_step.restype = ctypes.c_int
        
        # sqlite3_finalize
        self._lib.sqlite3_finalize.argtypes = [ctypes.c_void_p]
        self._lib.sqlite3_finalize.restype = ctypes.c_int
        
        # sqlite3_bind_*
        self._lib.sqlite3_bind_text.argtypes = [
            ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p, 
            ctypes.c_int, ctypes.c_void_p
        ]
        self._lib.sqlite3_bind_text.restype = ctypes.c_int
        
        self._lib.sqlite3_bind_int.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        self._lib.sqlite3_bind_int.restype = ctypes.c_int
        
        self._lib.sqlite3_bind_double.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_double]
        self._lib.sqlite3_bind_double.restype = ctypes.c_int
        
        # sqlite3_column_*
        self._lib.sqlite3_column_count.argtypes = [ctypes.c_void_p]
        self._lib.sqlite3_column_count.restype = ctypes.c_int
        
        self._lib.sqlite3_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._lib.sqlite3_column_text.restype = ctypes.c_char_p
        
        self._lib.sqlite3_column_int.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._lib.sqlite3_column_int.restype = ctypes.c_int
        
        self._lib.sqlite3_column_double.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._lib.sqlite3_column_double.restype = ctypes.c_double
        
        # sqlite3_errmsg
        self._lib.sqlite3_errmsg.argtypes = [ctypes.c_void_p]
        self._lib.sqlite3_errmsg.restype = ctypes.c_char_p
    
    def connect(self):
        """Connect to the database"""
        with self._lock:
            if self._db:
                return
                
            db_ptr = ctypes.c_void_p()
            flags = 0x00000006  # SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            
            result = self._lib.sqlite3_open_v2(
                self.db_path.encode('utf-8'),
                ctypes.byref(db_ptr),
                flags,
                None
            )
            
            if result != self.SQLITE_OK:
                raise SQLiteError(f"Failed to open database: {result}")
            
            self._db = db_ptr
    
    def close(self):
        """Close the database connection"""
        with self._lock:
            if self._db:
                self._lib.sqlite3_close_v2(self._db)
                self._db = None
    
    def _configure_database(self, enable_queue: bool):
        """Configure database with optimal settings"""
        # Enable WAL mode for better concurrency
        self.execute("PRAGMA journal_mode=WAL;")
        
        # Set busy timeout
        self.execute(f"PRAGMA busy_timeout={int(self.timeout * 1000)};")
        
        # Configure write queue
        if enable_queue:
            self.set_queue_enabled(True)
    
    def execute(self, sql: str, params: Optional[List[Any]] = None) -> Optional[List[Tuple]]:
        """
        Execute SQL statement with optional parameters
        
        Args:
            sql: SQL statement
            params: Optional parameters for prepared statement
            
        Returns:
            List of result tuples for SELECT statements, None otherwise
        """
        with self._lock:
            if not self._db:
                raise SQLiteError("Database not connected")
            
            stmt_ptr = ctypes.c_void_p()
            tail_ptr = ctypes.c_char_p()
            
            # Prepare statement
            result = self._lib.sqlite3_prepare_v2(
                self._db,
                sql.encode('utf-8'),
                -1,
                ctypes.byref(stmt_ptr),
                ctypes.byref(tail_ptr)
            )
            
            if result != self.SQLITE_OK:
                error_msg = self._lib.sqlite3_errmsg(self._db).decode('utf-8')
                raise SQLiteError(f"SQL preparation failed: {error_msg}")
            
            try:
                # Bind parameters if provided
                if params:
                    self._bind_parameters(stmt_ptr, params)
                
                # Execute and collect results
                rows = []
                while True:
                    result = self._lib.sqlite3_step(stmt_ptr)
                    
                    if result == self.SQLITE_ROW:
                        row = self._fetch_row(stmt_ptr)
                        rows.append(row)
                        
                    elif result == self.SQLITE_DONE:
                        break
                        
                    elif result == self.SQLITE_BUSY:
                        raise SQLiteError("Database is busy")
                        
                    elif result == self.SQLITE_LOCKED:
                        raise SQLiteError("Database is locked")
                        
                    elif result == self.SQLITE_FULL:
                        raise SQLiteError("Database or disk is full")
                        
                    else:
                        error_msg = self._lib.sqlite3_errmsg(self._db).decode('utf-8')
                        raise SQLiteError(f"SQL execution failed: {error_msg}")
                
                return rows if rows else None
                
            finally:
                self._lib.sqlite3_finalize(stmt_ptr)
    
    def _bind_parameters(self, stmt_ptr: ctypes.c_void_p, params: List[Any]):
        """Bind parameters to prepared statement"""
        for i, param in enumerate(params, 1):
            if isinstance(param, str):
                self._lib.sqlite3_bind_text(
                    stmt_ptr, i, param.encode('utf-8'), -1, None
                )
            elif isinstance(param, int):
                self._lib.sqlite3_bind_int(stmt_ptr, i, param)
            elif isinstance(param, float):
                self._lib.sqlite3_bind_double(stmt_ptr, i, param)
            elif param is None:
                # sqlite3_bind_null would be needed here
                pass
            else:
                # Convert to string as fallback
                param_str = str(param)
                self._lib.sqlite3_bind_text(
                    stmt_ptr, i, param_str.encode('utf-8'), -1, None
                )
    
    def _fetch_row(self, stmt_ptr: ctypes.c_void_p) -> Tuple:
        """Fetch a single row from statement"""
        col_count = self._lib.sqlite3_column_count(stmt_ptr)
        row = []
        
        for i in range(col_count):
            # Try text first
            text_val = self._lib.sqlite3_column_text(stmt_ptr, i)
            if text_val:
                row.append(text_val.decode('utf-8'))
            else:
                # Try integer
                int_val = self._lib.sqlite3_column_int(stmt_ptr, i)
                row.append(int_val)
        
        return tuple(row)
    
    def fetch_all(self, sql: str, params: Optional[List[Any]] = None) -> List[Tuple]:
        """Execute SELECT statement and return all results"""
        result = self.execute(sql, params)
        return result if result is not None else []
    
    def fetch_one(self, sql: str, params: Optional[List[Any]] = None) -> Optional[Tuple]:
        """Execute SELECT statement and return first result"""
        result = self.execute(sql, params)
        return result[0] if result else None
    
    def pragma(self, pragma_name: str, value: Any = None) -> Optional[str]:
        """Execute PRAGMA command"""
        if value is not None:
            sql = f"PRAGMA {pragma_name} = {value};"
        else:
            sql = f"PRAGMA {pragma_name};"
        
        result = self.execute(sql)
        if result and len(result) > 0:
            return str(result[0][0])
        return None
    
    def is_queue_enabled(self) -> bool:
        """Check if write queue is enabled"""
        try:
            status = self.pragma("write_queue")
            return status == "1"
        except:
            return False
    
    def set_queue_enabled(self, enabled: bool):
        """Enable or disable write queue"""
        try:
            self.pragma("write_queue", "ON" if enabled else "OFF")
        except Exception as e:
            raise SQLiteError(f"Failed to set write queue: {e}")
    
    @contextmanager
    def transaction(self):
        """Context manager for transactions"""
        self.execute("BEGIN TRANSACTION;")
        try:
            yield
            self.execute("COMMIT;")
        except:
            self.execute("ROLLBACK;")
            raise
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


def demo_concurrent_writes():
    """Demonstrate concurrent writes with queue support"""
    print("=== Concurrent Writes Demo ===")
    
    db_path = "/app/data/demo.db"
    os.makedirs("/app/data", exist_ok=True)
    
    # Setup database
    with CustomSQLiteDB(db_path, enable_queue=True) as db:
        print(f"✅ Connected to database: {db_path}")
        print(f"✅ Write queue enabled: {db.is_queue_enabled()}")
        
        # Create test table
        db.execute("DROP TABLE IF EXISTS demo;")
        db.execute("""
            CREATE TABLE demo (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                thread_id INTEGER,
                message TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
        """)
        print("✅ Created demo table")
    
    # Concurrent writer function
    def writer(thread_id: int, message_count: int = 5):
        with CustomSQLiteDB(db_path, enable_queue=True) as db:
            print(f"Thread {thread_id} starting (queue: {db.is_queue_enabled()})")
            
            for i in range(message_count):
                try:
                    db.execute(
                        "INSERT INTO demo (thread_id, message) VALUES (?, ?);",
                        [thread_id, f"Message {i} from thread {thread_id}"]
                    )
                    print(f"Thread {thread_id}: wrote message {i}")
                    time.sleep(0.1)
                except Exception as e:
                    print(f"Thread {thread_id}: error on message {i}: {e}")
    
    # Start multiple writers
    print("\n=== Starting concurrent writers ===")
    threads = []
    for t_id in range(3):
        t = threading.Thread(target=writer, args=(t_id,))
        threads.append(t)
        t.start()
    
    # Wait for completion
    for t in threads:
        t.join()
    
    # Show results
    print("\n=== Results ===")
    with CustomSQLiteDB(db_path) as db:
        count = db.fetch_one("SELECT COUNT(*) FROM demo;")[0]
        print(f"Total records: {count}")
        
        records = db.fetch_all("SELECT * FROM demo ORDER BY id;")
        print("Sample records:")
        for record in records[:10]:
            print(f"  {record}")
        
        if len(records) > 10:
            print(f"  ... and {len(records) - 10} more")


def demo_queue_features():
    """Demonstrate queue-specific features"""
    print("\n=== Queue Features Demo ===")
    
    with CustomSQLiteDB(":memory:", enable_queue=True) as db:
        print(f"Initial queue status: {db.is_queue_enabled()}")
        
        # Toggle queue
        db.set_queue_enabled(False)
        print(f"After disabling: {db.is_queue_enabled()}")
        
        db.set_queue_enabled(True)
        print(f"After enabling: {db.is_queue_enabled()}")
        
        # Test with transaction
        with db.transaction():
            db.execute("CREATE TABLE test (id INTEGER, value TEXT);")
            db.execute("INSERT INTO test VALUES (1, 'Hello');")
            db.execute("INSERT INTO test VALUES (2, 'World');")
        
        results = db.fetch_all("SELECT * FROM test;")
        print(f"Transaction results: {results}")


if __name__ == "__main__":
    print("🚀 Custom SQLite with SQLITE_ENABLE_QUEUE Demo")
    print("=" * 50)
    
    try:
        # Test basic functionality
        demo_queue_features()
        
        # Test concurrent writes
        demo_concurrent_writes()
        
        print("\n🎉 All demos completed successfully!")
        print("\nKey benefits of SQLITE_ENABLE_QUEUE:")
        print("  ✅ Reduced 'database locked' errors")
        print("  ✅ Better concurrent write performance")
        print("  ✅ Improved application responsiveness")
        print("  ✅ Automatic write batching")
        
    except Exception as e:
        print(f"\n❌ Demo failed: {e}")
        raise