// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PortMonitor", targets: ["PortMonitor"]),
        .executable(name: "PortMonitorCoreTests", targets: ["PortMonitorCoreTests"]),
        .library(name: "PortMonitorCore", targets: ["PortMonitorCore"])
    ],
    targets: [
        // C shim that reads socket info through libproc.
        .target(name: "CProcSockets"),

        // Pure, platform-independent logic (models + `lsof` parsing).
        .target(
            name: "PortMonitorCore",
            dependencies: ["CProcSockets"]
        ),

        // SwiftUI application shell.
        .executableTarget(
            name: "PortMonitor",
            dependencies: ["PortMonitorCore"]
        ),

        // A plain executable test runner (no XCTest) so tests run with or
        // without a full Xcode install.
        .executableTarget(
            name: "PortMonitorCoreTests",
            dependencies: ["PortMonitorCore"]
        )
    ]
)
