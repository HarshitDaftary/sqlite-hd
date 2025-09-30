#!/bin/bash

# Build script for iOS SQLite Framework with SQLITE_ENABLE_QUEUE support
# This script cross-compiles your custom SQLite for iOS architectures

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
IOS_DEPLOYMENT_TARGET="12.0"
FRAMEWORK_NAME="CustomSQLite"
BUILD_DIR="ios_build"
FRAMEWORK_DIR="$BUILD_DIR/framework"

# Xcode tools
XCODE_ROOT=$(xcode-select -print-path)
PLATFORM_PATH_IOS="$XCODE_ROOT/Platforms/iPhoneOS.platform"
PLATFORM_PATH_SIMULATOR="$XCODE_ROOT/Platforms/iPhoneSimulator.platform"

# SDK paths
SDK_IOS="$PLATFORM_PATH_IOS/Developer/SDKs/iPhoneOS.sdk"
SDK_SIMULATOR="$PLATFORM_PATH_SIMULATOR/Developer/SDKs/iPhoneSimulator.sdk"

# Architecture arrays
IOS_ARCHS=("arm64")
SIMULATOR_ARCHS=("arm64" "x86_64")

function check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v xcode-select >/dev/null; then
        print_error "Xcode command line tools not found!"
        exit 1
    fi
    
    if [ ! -d "$SDK_IOS" ]; then
        print_error "iOS SDK not found at $SDK_IOS"
        exit 1
    fi
    
    if [ ! -d "$SDK_SIMULATOR" ]; then
        print_error "iOS Simulator SDK not found at $SDK_SIMULATOR"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

function setup_build_environment() {
    print_info "Setting up build environment..."
    
    # Clean and create build directories
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$FRAMEWORK_DIR"
    
    # Create architecture-specific directories
    for arch in "${IOS_ARCHS[@]}"; do
        mkdir -p "$BUILD_DIR/ios-$arch"
    done
    
    for arch in "${SIMULATOR_ARCHS[@]}"; do
        mkdir -p "$BUILD_DIR/simulator-$arch"
    done
    
    print_success "Build environment ready"
}

function build_for_ios_device() {
    local arch=$1
    print_info "Building for iOS device architecture: $arch"
    
    local build_path="$BUILD_DIR/ios-$arch"
    cd "$build_path"
    
    # Configure environment
    export CC="$(xcrun -find clang)"
    export CXX="$(xcrun -find clang++)"
    export CFLAGS="-arch $arch -isysroot $SDK_IOS -mios-version-min=$IOS_DEPLOYMENT_TARGET -fembed-bitcode"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $arch -isysroot $SDK_IOS -mios-version-min=$IOS_DEPLOYMENT_TARGET"
    
    # Configure SQLite with queue support
    ../../configure \
        --host=arm-apple-darwin \
        --enable-static \
        --disable-shared \
        --enable-threadsafe \
        --disable-dynamic-extensions \
        CFLAGS="$CFLAGS -DSQLITE_ENABLE_QUEUE" \
        CXXFLAGS="$CXXFLAGS -DSQLITE_ENABLE_QUEUE"
    
    # Build
    make OPTIONS="-DSQLITE_ENABLE_QUEUE" sqlite3.c libsqlite3.a
    
    cd - >/dev/null
    print_success "Built for iOS device $arch"
}

function build_for_ios_simulator() {
    local arch=$1
    print_info "Building for iOS Simulator architecture: $arch"
    
    local build_path="$BUILD_DIR/simulator-$arch"
    cd "$build_path"
    
    # Configure environment
    export CC="$(xcrun -find clang)"
    export CXX="$(xcrun -find clang++)"
    export CFLAGS="-arch $arch -isysroot $SDK_SIMULATOR -mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $arch -isysroot $SDK_SIMULATOR -mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
    
    # Configure SQLite with queue support
    ../../configure \
        --enable-static \
        --disable-shared \
        --enable-threadsafe \
        --disable-dynamic-extensions \
        CFLAGS="$CFLAGS -DSQLITE_ENABLE_QUEUE" \
        CXXFLAGS="$CXXFLAGS -DSQLITE_ENABLE_QUEUE"
    
    # Build
    make OPTIONS="-DSQLITE_ENABLE_QUEUE" sqlite3.c libsqlite3.a
    
    cd - >/dev/null
    print_success "Built for iOS Simulator $arch"
}

function create_universal_libraries() {
    print_info "Creating universal libraries..."
    
    # Collect iOS device libraries
    local ios_libs=()
    for arch in "${IOS_ARCHS[@]}"; do
        ios_libs+=("$BUILD_DIR/ios-$arch/.libs/libsqlite3.a")
    done
    
    # Collect iOS simulator libraries  
    local simulator_libs=()
    for arch in "${SIMULATOR_ARCHS[@]}"; do
        simulator_libs+=("$BUILD_DIR/simulator-$arch/.libs/libsqlite3.a")
    done
    
    # Create universal libraries
    print_info "Creating iOS device universal library..."
    lipo -create "${ios_libs[@]}" -output "$BUILD_DIR/libsqlite3-ios.a"
    
    print_info "Creating iOS simulator universal library..."
    lipo -create "${simulator_libs[@]}" -output "$BUILD_DIR/libsqlite3-simulator.a"
    
    print_success "Universal libraries created"
}

function create_xcframework() {
    print_info "Creating XCFramework..."
    
    # Copy headers from one of the builds
    local header_source="$BUILD_DIR/ios-${IOS_ARCHS[0]}"
    
    # Create framework structure for iOS
    local ios_framework="$BUILD_DIR/ios_framework"
    mkdir -p "$ios_framework/$FRAMEWORK_NAME.framework/Headers"
    cp "$header_source/sqlite3.h" "$ios_framework/$FRAMEWORK_NAME.framework/Headers/"
    cp "$header_source/sqlite3ext.h" "$ios_framework/$FRAMEWORK_NAME.framework/Headers/"
    cp "$BUILD_DIR/libsqlite3-ios.a" "$ios_framework/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
    
    # Create Info.plist for iOS framework
    cat > "$ios_framework/$FRAMEWORK_NAME.framework/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.custom.sqlite</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>3.51.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF

    # Create framework structure for iOS Simulator
    local simulator_framework="$BUILD_DIR/simulator_framework"
    mkdir -p "$simulator_framework/$FRAMEWORK_NAME.framework/Headers"
    cp "$header_source/sqlite3.h" "$simulator_framework/$FRAMEWORK_NAME.framework/Headers/"
    cp "$header_source/sqlite3ext.h" "$simulator_framework/$FRAMEWORK_NAME.framework/Headers/"
    cp "$BUILD_DIR/libsqlite3-simulator.a" "$simulator_framework/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
    cp "$ios_framework/$FRAMEWORK_NAME.framework/Info.plist" "$simulator_framework/$FRAMEWORK_NAME.framework/"
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -framework "$ios_framework/$FRAMEWORK_NAME.framework" \
        -framework "$simulator_framework/$FRAMEWORK_NAME.framework" \
        -output "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
    
    print_success "XCFramework created at $FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
}

function create_swift_package() {
    print_info "Creating Swift Package..."
    
    local package_dir="$BUILD_DIR/SwiftPackage"
    mkdir -p "$package_dir/Sources/$FRAMEWORK_NAME"
    
    # Copy XCFramework
    cp -r "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework" "$package_dir/"
    
    # Create Package.swift
    cat > "$package_dir/Package.swift" << EOF
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "$FRAMEWORK_NAME",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "$FRAMEWORK_NAME",
            targets: ["$FRAMEWORK_NAME", "CustomSQLiteWrapper"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "$FRAMEWORK_NAME",
            path: "$FRAMEWORK_NAME.xcframework"
        ),
        .target(
            name: "CustomSQLiteWrapper",
            dependencies: ["$FRAMEWORK_NAME"],
            path: "Sources/$FRAMEWORK_NAME"
        )
    ]
)
EOF

    # Copy Swift wrapper
    cp "../CustomSQLite.swift" "$package_dir/Sources/$FRAMEWORK_NAME/"
    
    print_success "Swift Package created at $package_dir"
}

function create_usage_example() {
    print_info "Creating usage example..."
    
    local example_dir="$BUILD_DIR/Example"
    mkdir -p "$example_dir"
    
    # Create example iOS project files
    cat > "$example_dir/ViewController.swift" << 'EOF'
import UIKit

class ViewController: UIViewController {
    private var database: CustomSQLite?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupDatabase()
        testWriteQueue()
    }
    
    private func setupDatabase() {
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                       in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("app.db").path
            
            database = try CustomSQLite(path: dbPath)
            print("✅ Custom SQLite initialized with write queue support")
            
        } catch {
            print("❌ Database setup failed: \(error)")
        }
    }
    
    private func testWriteQueue() {
        guard let db = database else { return }
        
        do {
            // Test write queue functionality
            print("Write queue enabled: \(db.isWriteQueueEnabled())")
            
            // Create test table
            try db.createTable("messages", columns: [
                "id INTEGER PRIMARY KEY AUTOINCREMENT",
                "content TEXT NOT NULL",
                "timestamp DATETIME DEFAULT CURRENT_TIMESTAMP"
            ])
            
            // Test concurrent writes
            let group = DispatchGroup()
            
            for i in 0..<5 {
                group.enter()
                DispatchQueue.global().async {
                    do {
                        try db.insert(into: "messages", values: [
                            "content": "Message from thread \(i)"
                        ])
                        print("Thread \(i) completed")
                    } catch {
                        print("Thread \(i) error: \(error)")
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                do {
                    let count = try db.queryScalar("SELECT COUNT(*) FROM messages;")
                    print("Total messages: \(count ?? "0")")
                } catch {
                    print("Error counting messages: \(error)")
                }
            }
            
        } catch {
            print("❌ Write queue test failed: \(error)")
        }
    }
}
EOF

    print_success "Usage example created at $example_dir"
}

function main() {
    print_info "Building Custom SQLite for iOS with SQLITE_ENABLE_QUEUE support"
    print_info "================================================================="
    
    check_prerequisites
    setup_build_environment
    
    # Build for all architectures
    for arch in "${IOS_ARCHS[@]}"; do
        build_for_ios_device "$arch"
    done
    
    for arch in "${SIMULATOR_ARCHS[@]}"; do
        build_for_ios_simulator "$arch"
    done
    
    create_universal_libraries
    create_xcframework
    create_swift_package
    create_usage_example
    
    print_success "Build completed successfully!"
    print_info ""
    print_info "Generated files:"
    print_info "  📱 XCFramework: $FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
    print_info "  📦 Swift Package: $BUILD_DIR/SwiftPackage/"
    print_info "  💡 Usage Example: $BUILD_DIR/Example/"
    print_info ""
    print_info "Integration options:"
    print_info "  1. Drag & drop the XCFramework into your Xcode project"
    print_info "  2. Use the Swift Package Manager package"
    print_info "  3. Copy the Swift wrapper code to your project"
    print_info ""
    print_info "Your iOS app now has access to SQLITE_ENABLE_QUEUE features! 🎉"
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script must be run on macOS with Xcode installed"
    exit 1
fi

main "$@"