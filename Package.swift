// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CustomSQLite",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CustomSQLite",
            targets: ["CustomSQLite"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // No external dependencies - uses only system frameworks
    ],
    targets: [
        // Swift wrapper target
        .target(
            name: "CustomSQLite",
            dependencies: [],
            path: "Sources/CustomSQLite",
            exclude: [
                "README.md",
                "Examples/"
            ],
            sources: [
                "CustomSQLite.swift"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_ENABLE_QUEUE", to: "1"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_ENABLE_FTS4", to: "1"),
                .define("SQLITE_ENABLE_FTS5", to: "1"),
                .define("SQLITE_ENABLE_RTREE", to: "1"),
                .define("SQLITE_ENABLE_JSON1", to: "1"),
                .headerSearchPath("include"),
                .headerSearchPath("../../")
            ],
            cxxSettings: [
                .define("SQLITE_ENABLE_QUEUE", to: "1"),
                .define("SQLITE_THREADSAFE", to: "1")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        
        // Test target
        .testTarget(
            name: "CustomSQLiteTests",
            dependencies: ["CustomSQLite"],
            path: "Tests/CustomSQLiteTests"
        ),
        
        // Example target (optional)
        .executableTarget(
            name: "CustomSQLiteExample",
            dependencies: ["CustomSQLite"],
            path: "Sources/CustomSQLiteExample"
        )
    ]
)