#!/bin/bash

# SQLite Custom Build Script
# This script provides a convenient way to build SQLite Docker images
# with or without SQLITE_ENABLE_QUEUE support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENABLE_QUEUE="yes"
BUILD_TYPE="runtime"
IMAGE_TAG=""
VERBOSE=false

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show usage
show_usage() {
    cat << EOF
SQLite Custom Build Script

Usage: $0 [OPTIONS]

OPTIONS:
    -q, --queue ENABLE       Enable/disable SQLITE_ENABLE_QUEUE (yes|no, default: yes)
    -t, --type TYPE          Build type: runtime|development (default: runtime)
    -n, --name TAG           Custom image tag (default: auto-generated)
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

EXAMPLES:
    # Build with SQLITE_ENABLE_QUEUE enabled (default)
    $0

    # Build without SQLITE_ENABLE_QUEUE
    $0 --queue no

    # Build development image with tools
    $0 --type development

    # Build with custom tag
    $0 --name my-sqlite --queue yes

    # Build both configurations
    $0 --queue yes --name sqlite-with-queue
    $0 --queue no --name sqlite-without-queue

VERIFICATION:
    After building, you can verify the configuration:
    docker run --rm sqlite-custom:TAG sqlite-config

EOF
}

# Function to validate arguments
validate_args() {
    if [[ "$ENABLE_QUEUE" != "yes" && "$ENABLE_QUEUE" != "no" ]]; then
        print_error "Invalid queue option: $ENABLE_QUEUE. Must be 'yes' or 'no'"
        exit 1
    fi

    if [[ "$BUILD_TYPE" != "runtime" && "$BUILD_TYPE" != "development" ]]; then
        print_error "Invalid build type: $BUILD_TYPE. Must be 'runtime' or 'development'"
        exit 1
    fi
}

# Function to generate image tag if not provided
generate_tag() {
    if [[ -z "$IMAGE_TAG" ]]; then
        local queue_suffix=""
        if [[ "$ENABLE_QUEUE" == "yes" ]]; then
            queue_suffix="with-queue"
        else
            queue_suffix="without-queue"
        fi
        
        if [[ "$BUILD_TYPE" == "development" ]]; then
            IMAGE_TAG="sqlite-custom:dev-$queue_suffix"
        else
            IMAGE_TAG="sqlite-custom:$queue_suffix"
        fi
    fi
}

# Function to build Docker image
build_image() {
    print_info "Building SQLite Docker image..."
    print_info "Configuration:"
    print_info "  SQLITE_ENABLE_QUEUE: $ENABLE_QUEUE"
    print_info "  Build Type: $BUILD_TYPE"
    print_info "  Image Tag: $IMAGE_TAG"

    local docker_args=(
        "build"
        "-t" "$IMAGE_TAG"
        "--build-arg" "ENABLE_QUEUE=$ENABLE_QUEUE"
        "--target" "$BUILD_TYPE"
    )

    if [[ "$VERBOSE" == "true" ]]; then
        docker_args+=("--progress=plain")
    fi

    docker_args+=(".")

    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Running: docker ${docker_args[*]}"
    fi

    if docker "${docker_args[@]}"; then
        print_success "Build completed successfully!"
        print_info "Image tag: $IMAGE_TAG"
    else
        print_error "Build failed!"
        exit 1
    fi
}

# Function to verify build
verify_build() {
    print_info "Verifying build..."
    
    if docker run --rm "$IMAGE_TAG" sqlite-config; then
        print_success "Build verification passed!"
    else
        print_warning "Build verification failed or image doesn't support sqlite-config"
    fi

    # Test basic SQLite functionality
    print_info "Testing basic SQLite functionality..."
    if docker run --rm "$IMAGE_TAG" sqlite3 --version; then
        print_success "SQLite version check passed!"
    else
        print_error "SQLite version check failed!"
        exit 1
    fi

    # If queue is enabled, try to test the functionality
    if [[ "$ENABLE_QUEUE" == "yes" ]]; then
        print_info "Testing SQLITE_ENABLE_QUEUE functionality..."
        if docker run --rm "$IMAGE_TAG" sqlite3 <<< "PRAGMA write_queue;" | grep -q "0\|1"; then
            print_success "SQLITE_ENABLE_QUEUE functionality verified!"
        else
            print_warning "Could not verify SQLITE_ENABLE_QUEUE functionality"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--queue)
            ENABLE_QUEUE="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -n|--name)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_info "SQLite Custom Build Script"
    print_info "=========================="

    # Validate arguments
    validate_args

    # Generate tag if needed
    generate_tag

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi

    # Build the image
    build_image

    # Verify the build
    verify_build

    print_success "All done! You can now use the image: $IMAGE_TAG"
    print_info ""
    print_info "Quick start commands:"
    print_info "  # Run interactive SQLite shell:"
    print_info "  docker run -it --rm -v \$(pwd)/data:/data $IMAGE_TAG"
    print_info ""
    print_info "  # Check build configuration:"
    print_info "  docker run --rm $IMAGE_TAG sqlite-config"
    print_info ""
    print_info "  # Run with custom database file:"
    print_info "  docker run -it --rm -v \$(pwd)/data:/data $IMAGE_TAG sqlite3 /data/mydb.sqlite"
}

# Run main function
main "$@"