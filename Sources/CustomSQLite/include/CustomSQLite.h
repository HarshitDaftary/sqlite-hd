#ifndef CUSTOMSQLITE_H
#define CUSTOMSQLITE_H

// Forward declarations for SQLite with SQLITE_ENABLE_QUEUE support
// This header ensures the correct SQLite library is used

#define SQLITE_ENABLE_QUEUE 1
#define SQLITE_THREADSAFE 1
#define SQLITE_ENABLE_FTS4 1
#define SQLITE_ENABLE_FTS5 1
#define SQLITE_ENABLE_RTREE 1
#define SQLITE_ENABLE_JSON1 1

// Include the custom SQLite header
#include "sqlite3.h"

#endif /* CUSTOMSQLITE_H */