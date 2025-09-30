# Write Queue Feature

## Overview

The write queue feature (`PRAGMA write_queue`) is an **experimental** feature that provides a pragma interface for managing write queue settings in SQLite. This feature is controlled by the `SQLITE_ENABLE_QUEUE` compile-time flag.

**IMPORTANT**: This is a work-in-progress feature. The pragma interface is functional, but the underlying queue implementation for multi-consumer writes is still under development. The current implementation allows you to:
- Query the write queue status via `PRAGMA write_queue`
- Enable/disable the write queue flag at runtime
- Build and export libraries with the feature enabled

## Building with Write Queue Support

### Using the Configure Script

To build SQLite with write queue support, use the `--write-queue` flag:

```bash
./configure --write-queue
make
```

This will define `SQLITE_ENABLE_QUEUE` during compilation and make the `PRAGMA write_queue` available.

### Verification

After building, verify the pragma is available:

```bash
./sqlite3 :memory: "PRAGMA write_queue;"
```

If successful, this will return `1` (enabled by default) or `0` (disabled).

### Manual Build

Alternatively, you can enable it manually by defining `SQLITE_ENABLE_QUEUE`:

```bash
gcc -DSQLITE_ENABLE_QUEUE -o sqlite3 shell.c sqlite3.c -lpthread -ldl
```

### Building a Shared Library

To build a shared library with write queue support (for use with Python, Ruby, etc.):

```bash
./configure --write-queue
make libsqlite3.so     # On Linux
# or
make libsqlite3.dylib  # On macOS
```

## Using the Write Queue Pragma

### Query the Current State

```sql
PRAGMA write_queue;
```

Returns:
- `1` if write queue is enabled (default when compiled with `SQLITE_ENABLE_QUEUE`)
- `0` if write queue is disabled

### Enable/Disable the Write Queue

```sql
-- Enable
PRAGMA write_queue = ON;
PRAGMA write_queue = 1;

-- Disable
PRAGMA write_queue = OFF;
PRAGMA write_queue = 0;

-- Verify
PRAGMA write_queue;
```

## Using with Python

When building a library for Python (e.g., for use with `apsw` or custom SQLite bindings):

```python
import apsw  # or sqlite3 with custom build

conn = apsw.Connection("mydb.db")
cursor = conn.cursor()

# Check if pragma is available
try:
    result = cursor.execute("PRAGMA write_queue").fetchone()
    print(f"write_queue: {result[0]}")
except Exception as e:
    print(f"write_queue pragma not available: {e}")
```

## Important Notes

### Current Status

This is an **experimental and incomplete** feature. The pragma interface works and can be queried/set, but:

1. **Implementation in progress**: The underlying write queue mechanism for true multi-consumer writes is still being developed
2. **Single-writer still enforced**: SQLite's fundamental locking mechanisms still enforce single-writer semantics
3. **Best effort basis**: This feature should be considered alpha quality

### Limitations

1. **Single-writer semantics**: Even with the queue enabled, SQLite fundamentally enforces single-writer semantics
2. **Schema writes**: Writes to page 1 (schema/change-counter) are not queued
3. **Queue size**: The queue has a maximum size defined by `SQLITE_QUEUE_MAX` (default: 128 entries)

### For Production Use

For production environments needing concurrent writes, consider:

1. **WAL mode**: Use `PRAGMA journal_mode=WAL` for better concurrency
2. **Busy timeout**: Set appropriate `PRAGMA busy_timeout` values
3. **Application-level queuing**: Implement write queuing at the application level
4. **Connection pooling**: Use connection pooling with retry logic

### WAL Mode and Busy Timeout (Recommended)

Even without full write queue support, these help with concurrent access:

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;  -- 5 seconds
```

## Testing

### Check Feature Availability

```bash
# Build with feature enabled
./configure --write-queue
make sqlite3

# Test pragma
./sqlite3 :memory: "PRAGMA write_queue;"
# Should output: 1
```

### Verify in Configuration

```bash
# During configuration
./configure --write-queue 2>&1 | grep write-queue
# Should show: + write-queue

# Check library feature flags
./configure --write-queue 2>&1 | grep "Library feature flags"
# Should include: -DSQLITE_ENABLE_QUEUE
```

## See Also

- `PRAGMA journal_mode` - WAL mode documentation
- `PRAGMA busy_timeout` - Busy timeout documentation  
- `test/write_queue.test` - Test suite for write queue pragma
