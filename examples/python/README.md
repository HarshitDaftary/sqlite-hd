# Python Examples

This directory contains Python examples showing how to use CustomSQLite with SQLITE_ENABLE_QUEUE support.

## Examples

### production_sqlite.py
Production-ready Python wrapper with:
- Context manager for safe database handling
- Parameter binding for security
- Queue status checking
- Error handling

### python_ctypes_test.py
Direct ctypes integration showing:
- Low-level SQLite library access
- Custom library loading
- Performance testing
- Concurrent write testing

### python_native_test.py
Native Python integration approach using:
- Subprocess calls to custom sqlite3 binary
- Simple command-line interface
- Basic functionality testing

### python_subprocess_test.py
Subprocess-based approach with:
- Process management
- Output parsing
- Error handling
- Performance comparison

### custom_sqlite_test.py
Quick test script for:
- Basic functionality verification
- Queue feature testing
- Simple benchmarking

### main.py
Simple demo script showing:
- Basic database operations
- Queue enablement verification
- Quick performance test

## Usage

### Docker (Recommended)
```bash
docker run --rm -v $(pwd)/data:/app/data harshitdaftary/sqlite-queue-python
```

### Direct Usage
```python
from production_sqlite import CustomSQLiteDB

with CustomSQLiteDB('database.db', enable_queue=True) as db:
    print(f"Queue enabled: {db.is_queue_enabled()}")
    # Your database operations here
```

See the main [Python Solutions Guide](../../PYTHON_SOLUTIONS.md) for complete integration instructions.