import apsw
import os
import threading
import time

# Set environment variable to use custom SQLite library
os.environ["DYLD_LIBRARY_PATH"] = os.path.dirname(os.path.abspath("libsqlite3.dylib"))

def writer(thread_id):
    conn = apsw.Connection("mydb.sqlite")
    cursor = conn.cursor()
    # Set write_queue pragma ON for each connection
    try:
        cursor.execute("PRAGMA write_queue=ON;")
        for row in cursor.execute("PRAGMA write_queue;"):
            print(f"Thread {thread_id} write_queue value: {row}")
    except Exception as e:
        print(f"Thread {thread_id} pragma error: {e}")
    for i in range(10):
        try:
            cursor.execute("INSERT INTO test (value) VALUES (?)", (f"thread-{thread_id}-val-{i}",))
            print(f"Thread {thread_id} wrote value {i}")
        except Exception as e:
            print(f"Thread {thread_id} error: {e}")
        time.sleep(0.1)
    conn.close()

# Create table if not exists and set write_queue ON
conn = apsw.Connection("mydb.sqlite")
cursor = conn.cursor()


cursor.execute('PRAGMA journal_mode=WAL;')
cursor.execute('PRAGMA busy_timeout=5000;')
cursor.execute("PRAGMA write_queue=ON;")
cursor.execute("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, value TEXT)")
conn.close()

# Start multiple writer threads
threads = []
for t_id in range(5):
    t = threading.Thread(target=writer, args=(t_id,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

# Print all rows
conn = apsw.Connection("mydb.sqlite")
cursor = conn.cursor()
for row in cursor.execute("SELECT * FROM test"):
    print(row)


for row in cursor.execute("PRAGMA write_queue;"):
    print("write_queue:", row)

conn.close()
