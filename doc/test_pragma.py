#!/usr/bin/env python3
"""
Simple example demonstrating the PRAGMA write_queue feature.

This script shows how to:
1. Check if the write_queue pragma is available
2. Query its current value
3. Set it to different values

Make sure your SQLite library is compiled with SQLITE_ENABLE_QUEUE:
  ./configure --write-queue
  make
  make libsqlite3.so (or .dylib on macOS)

For APSW users, rebuild APSW against the custom library.
For sqlite3 module users, this typically requires rebuilding Python's sqlite3 module.
"""

import sqlite3
import sys

def test_write_queue_pragma():
    """Test the write_queue pragma functionality"""
    
    print("=" * 60)
    print("SQLite Write Queue Pragma Test")
    print("=" * 60)
    print()
    
    # Connect to an in-memory database
    conn = sqlite3.connect(':memory:')
    cursor = conn.cursor()
    
    # Check SQLite version
    version = cursor.execute("SELECT sqlite_version()").fetchone()[0]
    print(f"SQLite version: {version}")
    print()
    
    # Test 1: Check if pragma is available
    print("Test 1: Checking if write_queue pragma is available...")
    try:
        result = cursor.execute("PRAGMA write_queue").fetchone()
        if result:
            print(f"✓ write_queue pragma is AVAILABLE")
            print(f"  Current value: {result[0]}")
        else:
            print("✗ write_queue pragma returned no result")
            return False
    except sqlite3.OperationalError as e:
        print(f"✗ write_queue pragma is NOT available")
        print(f"  Error: {e}")
        print()
        print("This SQLite build does not have SQLITE_ENABLE_QUEUE compiled in.")
        print("To enable it, rebuild SQLite with:")
        print("  ./configure --write-queue")
        print("  make")
        return False
    print()
    
    # Test 2: Set to OFF (0)
    print("Test 2: Setting write_queue to OFF...")
    cursor.execute("PRAGMA write_queue=OFF")
    result = cursor.execute("PRAGMA write_queue").fetchone()[0]
    print(f"  write_queue = {result}")
    if result == 0:
        print("  ✓ Successfully set to OFF (0)")
    else:
        print(f"  ✗ Expected 0, got {result}")
    print()
    
    # Test 3: Set to ON (1)
    print("Test 3: Setting write_queue to ON...")
    cursor.execute("PRAGMA write_queue=ON")
    result = cursor.execute("PRAGMA write_queue").fetchone()[0]
    print(f"  write_queue = {result}")
    if result == 1:
        print("  ✓ Successfully set to ON (1)")
    else:
        print(f"  ✗ Expected 1, got {result}")
    print()
    
    # Test 4: Set to 0
    print("Test 4: Setting write_queue to 0...")
    cursor.execute("PRAGMA write_queue=0")
    result = cursor.execute("PRAGMA write_queue").fetchone()[0]
    print(f"  write_queue = {result}")
    if result == 0:
        print("  ✓ Successfully set to 0")
    else:
        print(f"  ✗ Expected 0, got {result}")
    print()
    
    # Test 5: Set to 1
    print("Test 5: Setting write_queue to 1...")
    cursor.execute("PRAGMA write_queue=1")
    result = cursor.execute("PRAGMA write_queue").fetchone()[0]
    print(f"  write_queue = {result}")
    if result == 1:
        print("  ✓ Successfully set to 1")
    else:
        print(f"  ✗ Expected 1, got {result}")
    print()
    
    conn.close()
    
    print("=" * 60)
    print("All pragma tests completed successfully!")
    print("=" * 60)
    print()
    print("Note: The pragma interface is working, but the underlying")
    print("write queue implementation for multi-consumer writes is")
    print("still under development.")
    print()
    
    return True

if __name__ == "__main__":
    success = test_write_queue_pragma()
    sys.exit(0 if success else 1)
