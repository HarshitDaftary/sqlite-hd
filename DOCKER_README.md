# SQLite Custom Docker Build

This Docker setup allows you to build and use a custom version of SQLite with optional `SQLITE_ENABLE_QUEUE` support. The queue feature provides smoother multi-writer SQLite behavior by reducing `SQLITE_BUSY` retries through a write queue mechanism.

## Features

- **Configurable Build**: Enable or disable `SQLITE_ENABLE_QUEUE` at build time
- **Multi-Stage Build**: Optimized production images with minimal dependencies
- **Development Support**: Separate development image with build tools
- **Easy Usage**: Convenient build script and Docker Compose configurations
- **Verification**: Built-in verification of build configuration

## Quick Start

### Using the Build Script (Recommended)

```bash
# Build with SQLITE_ENABLE_QUEUE enabled (default)
./build.sh

# Build without SQLITE_ENABLE_QUEUE
./build.sh --queue no

# Build development image
./build.sh --type development

# Custom image name
./build.sh --name my-sqlite --queue yes
```

### Using Docker Commands Directly

```bash
# Build with SQLITE_ENABLE_QUEUE (default)
docker build -t sqlite-custom:with-queue .

# Build without SQLITE_ENABLE_QUEUE
docker build -t sqlite-custom:without-queue --build-arg ENABLE_QUEUE=no .

# Build development image
docker build -t sqlite-custom:dev --target development .
```

### Using Docker Compose

```bash
# Build and run with queue support
docker-compose --profile with-queue up

# Build and run without queue support
docker-compose --profile without-queue up

# Build both configurations
docker-compose --profile all up

# Development environment
docker-compose --profile dev up -d
docker-compose exec sqlite-dev bash
```

## Usage Examples

### Running SQLite Interactively

```bash
# Create a data directory
mkdir -p data

# Run SQLite with a mounted volume
docker run -it --rm -v $(pwd)/data:/data sqlite-custom:with-queue

# Or start a database file directly
docker run -it --rm -v $(pwd)/data:/data sqlite-custom:with-queue sqlite3 /data/mydb.sqlite
```

### Checking Build Configuration

```bash
# View build configuration and features
docker run --rm sqlite-custom:with-queue sqlite-config
```

### Testing SQLITE_ENABLE_QUEUE Feature

```bash
# Connect to SQLite and test the write_queue pragma
docker run -it --rm sqlite-custom:with-queue sqlite3 << EOF
PRAGMA write_queue;
PRAGMA write_queue = ON;
PRAGMA write_queue;
.quit
EOF
```

### Using as Base Image

```dockerfile
FROM sqlite-custom:with-queue

# Install your application
COPY myapp /usr/local/bin/
RUN chmod +x /usr/local/bin/myapp

# Use the custom SQLite
CMD ["myapp"]
```

## Build Configurations

### Available Build Arguments

- `ENABLE_QUEUE`: `yes` (default) or `no`
- `ALPINE_VERSION`: Alpine Linux version (default: `3.19`)

### Available Targets

- `runtime` (default): Minimal production image
- `development`: Full development environment with build tools
- `builder`: Intermediate build stage (not typically used directly)

## File Structure

After building, the container includes:

```
/usr/local/bin/sqlite3          # SQLite CLI binary
/usr/local/lib/libsqlite3.*     # SQLite libraries (shared and static)
/usr/local/include/sqlite3*.h   # SQLite headers
/usr/local/src/sqlite3.c        # SQLite amalgamation source
/usr/local/share/sqlite-build-config  # Build configuration info
/usr/local/bin/sqlite-config    # Configuration display script
```

## SQLITE_ENABLE_QUEUE Feature

The `SQLITE_ENABLE_QUEUE` feature implements a write queue mechanism to reduce contention between concurrent writers. Key benefits:

- **Reduced SQLITE_BUSY errors**: Fewer retry loops in write-heavy applications
- **Better perceived latency**: Writers don't block waiting for the write lock
- **Batched writes**: Improved I/O efficiency through write queuing

### Using the Write Queue

```sql
-- Check if write queue is available and current status
PRAGMA write_queue;

-- Enable write queue (if compiled with SQLITE_ENABLE_QUEUE)
PRAGMA write_queue = ON;

-- Disable write queue
PRAGMA write_queue = OFF;
```

### Queue Behavior

1. **Valid writes with lock free**: Applied immediately
2. **Valid writes while lock held**: Queued for later execution (returns success immediately)
3. **Invalid writes**: Rejected before queuing (syntax errors, constraint violations, etc.)
4. **Queue full**: Returns `SQLITE_FULL` error

## Development Workflow

### Setting Up Development Environment

```bash
# Start development container
./build.sh --type development --name sqlite-dev
docker run -it --rm -v $(pwd):/workspace sqlite-dev bash

# Or use Docker Compose
docker-compose --profile dev up -d
docker-compose exec sqlite-dev bash
```

### Building and Testing Changes

```bash
# Inside the development container
cd /workspace
mkdir -p bld && cd bld

# Configure with your desired features
../configure --enable-all

# Build
make sqlite3
make sqlite3.c

# Test
make test
```

### Debugging

The development image includes debugging tools:

- `gdb`: GNU Debugger
- `valgrind`: Memory debugging
- `strace`: System call tracing

```bash
# Debug with gdb
gdb ./sqlite3
(gdb) run mydatabase.db

# Check for memory leaks
valgrind --leak-check=full ./sqlite3 mydatabase.db

# Trace system calls
strace ./sqlite3 mydatabase.db
```

## Comparison with System SQLite

To compare the custom build with system SQLite:

```bash
# System SQLite version
sqlite3 --version

# Custom SQLite version
docker run --rm sqlite-custom:with-queue sqlite3 --version

# Feature comparison
echo "PRAGMA compile_options;" | sqlite3
echo "PRAGMA compile_options;" | docker run -i --rm sqlite-custom:with-queue sqlite3
```

## Performance Considerations

### With SQLITE_ENABLE_QUEUE

**Pros:**
- Reduced contention in write-heavy workloads
- Better tail latency under concurrent writes
- Fewer application retry loops
- Improved battery life on mobile (fewer busy-wait cycles)

**Cons:**
- Slightly increased memory usage (queue buffer)
- Additional complexity in write path
- Queue can fill up under extreme load (`SQLITE_FULL` errors)

### Configuration Tuning

The write queue size is configurable at compile time:

```c
#ifndef SQLITE_QUEUE_MAX
#define SQLITE_QUEUE_MAX 128  // Default queue size
#endif
```

To customize, modify the `OPT_FEATURE_FLAGS` in the Dockerfile:

```dockerfile
RUN export OPT_FEATURE_FLAGS="-DSQLITE_ENABLE_QUEUE -DSQLITE_QUEUE_MAX=256"
```

## Security Considerations

- The container runs as a non-root user (`sqlite:sqlite`, UID/GID 1000)
- Minimal attack surface with Alpine Linux base
- No unnecessary packages in production image
- Read-only source code in development image

## Troubleshooting

### Build Issues

1. **Configure fails**: Ensure you have a clean source tree
2. **Missing dependencies**: The Dockerfile should handle all dependencies
3. **Permission issues**: Make sure Docker has access to the source directory

### Runtime Issues

1. **Permission denied**: Check volume mount permissions
2. **Feature not available**: Verify build configuration with `sqlite-config`
3. **Database lock issues**: Ensure proper connection management in your application

### Verification Steps

```bash
# Check if the image was built correctly
docker images | grep sqlite-custom

# Verify configuration
docker run --rm sqlite-custom:with-queue sqlite-config

# Test basic functionality
docker run --rm sqlite-custom:with-queue sqlite3 --version

# Check for SQLITE_ENABLE_QUEUE
docker run --rm sqlite-custom:with-queue sqlite3 << EOF
PRAGMA compile_options;
EOF
```

## Contributing

To contribute improvements to this Docker setup:

1. Test your changes with both `ENABLE_QUEUE=yes` and `ENABLE_QUEUE=no`
2. Verify the build script works correctly
3. Update documentation as needed
4. Test with both runtime and development targets

## Resources

- [SQLite Documentation](https://sqlite.org/docs.html)
- [Write Queue Feature Documentation](./write-queue-concurrency.md)
- [SQLite Compilation Options](https://sqlite.org/compile.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)