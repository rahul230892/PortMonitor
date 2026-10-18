// swift-tools-version:5.9
import PackageDescription
import Foundation

// XCTest is only available with a full Xcode install, which this project does
// not assume. The canonical suite is the dependency-free executable runner
// (`PortMonitorCoreTests`, run via `make test`); the XCTest target below is an
// opt-in mirror of it for machines that do have Xcode:
//
//     PORTMONITOR_ENABLE_XCTEST=1 swift test      # or: make test-xctest
//
// Keeping it behind an environment variable means plain `swift build` on a
// Command Line Tools-only machine never tries to link XCTest.
let enableXCTest = ProcessInfo.processInfo.environment["PORTMONITOR_ENABLE_XCTEST"] == "1"

var targets: [Target] = [
    // C shim that reads socket info through libproc.
    .target(name: "CProcSockets"),

    // Pure, platform-independent logic (models + parsers + providers).
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

if enableXCTest {
    targets.append(
        .testTarget(
            name: "PortMonitorXCTests",
            dependencies: ["PortMonitorCore"]
        )
    )
}

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
    targets: targets
)
