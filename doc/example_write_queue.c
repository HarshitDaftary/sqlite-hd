/*
** Example: Using the Write Queue Pragma
**
** This example demonstrates how to check for and use the PRAGMA write_queue
** feature in SQLite. The write queue is an experimental feature for managing
** write operations.
**
** NOTE: This example demonstrates the pragma interface. The underlying write
** queue implementation for multi-consumer writes is still under development,
** so you may still encounter "database locked" errors in concurrent scenarios.
**
** Compile with:
**   gcc -o example_write_queue example_write_queue.c -lsqlite3 -lpthread
**
** Make sure you're linking against a version of SQLite compiled with
** -DSQLITE_ENABLE_QUEUE (use: ./configure --write-queue && make)
*/

#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

#define NUM_THREADS 5
#define WRITES_PER_THREAD 10

typedef struct {
    int thread_id;
    const char *db_path;
} thread_data_t;

void* writer_thread(void* arg) {
    thread_data_t *data = (thread_data_t*)arg;
    sqlite3 *db;
    char *err_msg = NULL;
    int rc;
    
    // Open database connection
    rc = sqlite3_open(data->db_path, &db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Thread %d: Cannot open database: %s\n", 
                data->thread_id, sqlite3_errmsg(db));
        return NULL;
    }
    
    // Enable WAL mode
    rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Thread %d: WAL mode error: %s\n", data->thread_id, err_msg);
        sqlite3_free(err_msg);
    }
    
    // Set busy timeout
    rc = sqlite3_exec(db, "PRAGMA busy_timeout=5000", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Thread %d: Busy timeout error: %s\n", data->thread_id, err_msg);
        sqlite3_free(err_msg);
    }
    
    // Enable write queue
    rc = sqlite3_exec(db, "PRAGMA write_queue=ON", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Thread %d: Write queue error: %s\n", data->thread_id, err_msg);
        sqlite3_free(err_msg);
    }
    
    // Verify write queue is enabled
    sqlite3_stmt *stmt;
    rc = sqlite3_prepare_v2(db, "PRAGMA write_queue", -1, &stmt, NULL);
    if (rc == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int queue_status = sqlite3_column_int(stmt, 0);
            printf("Thread %d: write_queue = %d\n", data->thread_id, queue_status);
        }
        sqlite3_finalize(stmt);
    }
    
    // Perform writes
    int success_count = 0;
    for (int i = 0; i < WRITES_PER_THREAD; i++) {
        char sql[256];
        snprintf(sql, sizeof(sql), 
                 "INSERT INTO test (thread_id, value) VALUES (%d, 'thread-%d-val-%d')",
                 data->thread_id, data->thread_id, i);
        
        // Use BEGIN/COMMIT for proper transaction handling
        sqlite3_exec(db, "BEGIN", NULL, NULL, NULL);
        rc = sqlite3_exec(db, sql, NULL, NULL, &err_msg);
        if (rc == SQLITE_OK) {
            sqlite3_exec(db, "COMMIT", NULL, NULL, NULL);
            success_count++;
        } else {
            fprintf(stderr, "Thread %d: Insert error at %d: %s\n", 
                    data->thread_id, i, err_msg);
            sqlite3_free(err_msg);
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        }
        
        // Small delay to simulate work
        usleep(10000); // 10ms
    }
    
    printf("Thread %d: Completed %d/%d writes\n", 
           data->thread_id, success_count, WRITES_PER_THREAD);
    
    sqlite3_close(db);
    return NULL;
}

int main(int argc, char *argv[]) {
    const char *db_path = argc > 1 ? argv[1] : "test_write_queue.db";
    sqlite3 *db;
    char *err_msg = NULL;
    int rc;
    
    printf("=== SQLite Write Queue Example ===\n\n");
    
    // Remove existing database
    remove(db_path);
    
    // Create database and table
    printf("Creating database: %s\n", db_path);
    rc = sqlite3_open(db_path, &db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        return 1;
    }
    
    // Check if write_queue pragma is available
    sqlite3_stmt *stmt;
    rc = sqlite3_prepare_v2(db, "PRAGMA write_queue", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "\nERROR: write_queue pragma not available!\n");
        fprintf(stderr, "This SQLite build was not compiled with SQLITE_ENABLE_QUEUE.\n");
        fprintf(stderr, "Please rebuild with: ./configure --write-queue && make\n\n");
        sqlite3_close(db);
        return 1;
    }
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        int queue_status = sqlite3_column_int(stmt, 0);
        printf("write_queue pragma is available (current value: %d)\n\n", queue_status);
    }
    sqlite3_finalize(stmt);
    
    // Enable WAL mode
    rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "WAL mode error: %s\n", err_msg);
        sqlite3_free(err_msg);
        sqlite3_close(db);
        return 1;
    }
    
    // Enable write queue
    rc = sqlite3_exec(db, "PRAGMA write_queue=ON", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Write queue error: %s\n", err_msg);
        sqlite3_free(err_msg);
    }
    
    // Create test table
    rc = sqlite3_exec(db, 
        "CREATE TABLE test ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  thread_id INTEGER,"
        "  value TEXT"
        ")", NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Create table error: %s\n", err_msg);
        sqlite3_free(err_msg);
        sqlite3_close(db);
        return 1;
    }
    
    sqlite3_close(db);
    
    // Start concurrent writer threads
    printf("Starting %d concurrent writer threads...\n", NUM_THREADS);
    pthread_t threads[NUM_THREADS];
    thread_data_t thread_data[NUM_THREADS];
    
    for (int i = 0; i < NUM_THREADS; i++) {
        thread_data[i].thread_id = i;
        thread_data[i].db_path = db_path;
        pthread_create(&threads[i], NULL, writer_thread, &thread_data[i]);
    }
    
    // Wait for all threads
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    
    // Verify results
    printf("\n=== Verification ===\n");
    rc = sqlite3_open(db_path, &db);
    if (rc == SQLITE_OK) {
        rc = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM test", -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                int count = sqlite3_column_int(stmt, 0);
                printf("Total records: %d\n", count);
                
                int expected = NUM_THREADS * WRITES_PER_THREAD;
                if (count == expected) {
                    printf("✓ SUCCESS: All %d writes completed!\n", expected);
                } else {
                    printf("⚠ WARNING: Expected %d records, got %d\n", expected, count);
                }
            }
            sqlite3_finalize(stmt);
        }
        
        // Show per-thread counts
        rc = sqlite3_prepare_v2(db, 
            "SELECT thread_id, COUNT(*) FROM test GROUP BY thread_id ORDER BY thread_id", 
            -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                int tid = sqlite3_column_int(stmt, 0);
                int count = sqlite3_column_int(stmt, 1);
                printf("  Thread %d: %d records\n", tid, count);
            }
            sqlite3_finalize(stmt);
        }
        
        sqlite3_close(db);
    }
    
    printf("\n");
    return 0;
}
