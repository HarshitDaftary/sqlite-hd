## Smoother Multi-Writer SQLite (Experimental)

Mobile & Python devs know this: two parts of your app write at once -> one hits SQLITE_BUSY and retries. WAL mode fixes readers-vs-writer, but not writer-vs-writer: only one connection can hold the internal write lock.

### Problem (Technical Framing)
Concurrent write transactions contend on a single internal write lock. Even tiny updates (e.g. incrementing a counter) must wait, so calls can return `SQLITE_BUSY` and retry. Under bursty workloads (sync, background tasks, batched analytics) this serialization inflates tail latency, increases retry/backoff loops, and wastes CPU/battery. WAL mode separates readers from writers but does not remove writer-vs-writer contention. Result: jittery write performance and unpredictable latency spikes.

### Simple Idea
We add a fixed-size ring buffer (FIFO queue array) in front of the internal “only one writer at a time” lock:
1. Valid write request arrives, lock free → apply immediately.
2. Valid write arrives while another write is in progress → if it does not touch core schema data (first block), enqueue a small record and return success (no waiting / no retry loop).
3. Lock releases → drain queued items FIFO, applying each.

Validation happens first: invalid SQL (syntax error, missing table, constraint failure) never reaches this queue stage, so only safe, already‑checked writes are enqueued. Queue details: bounded array + head, tail, count. If full -> `SQLITE_FULL`. The first block (schema + counters) always bypasses the queue for integrity.

### What You Get
- Fewer SQLITE_BUSY retries
- Shorter perceived write latency
- Small batched disk writes
- Toggle with: PRAGMA write_queue = ON|OFF

We did not make disk I/O parallel; we decoupled producers from the critical section using a bounded ring buffer, reducing visible contention.