import Foundation

/// Dependency-free test runner.
///
/// This project intentionally avoids XCTest so the tests build and run with a
/// plain Command Line Tools toolchain (no Xcode required), both locally and in CI.
let tests: [(name: String, run: () throws -> Void)] = [
    ("parses listening TCP entries and applies default state", testParsesListeningTCPEntriesAndAppliesDefaultState),
    ("preserves command names containing spaces", testPreservesCommandNamesContainingSpaces),
    ("skips unbound UDP entries", testSkipsUnboundUDPEntries),
    ("uses local side and state for connected sockets", testUsesLocalSideAndStateForConnectedSockets),
    ("unwraps IPv6 hosts", testUnwrapsIPv6Host),
    ("ignores malformed and irrelevant lines", testIgnoresMalformedAndIrrelevantLines),
    ("provider combines TCP and UDP and sorts by port", testProviderCombinesTCPAndUDPAndSortsByPort),
    ("provider reports a missing tool", testProviderReportsMissingTool),
    ("real provider runs on this host", testRealProviderRunsOnThisHost),
    ("fallback uses first non-empty provider", testFallbackUsesFirstNonEmptyProvider),
    ("fallback skips empty and erroring providers", testFallbackSkipsEmptyAndErroringProviders),
    ("fallback rethrows when all providers fail", testFallbackRethrowsWhenAllProvidersFail),
    ("native provider returns sorted in-range ports", testNativeProviderReturnsSortedInRangePorts),
    ("native and lsof agree on TCP listeners", testNativeAndLsofAgreeOnTcpListeners),
    ("provider kind builds expected providers", testProviderKindBuildsExpectedProviders),
    ("identifier is stable and distinguishes sockets", testIdentifierIsStableAndDistinguishesSockets)
]

var passed = 0
var failed: [String] = []

for test in tests {
    do {
        try test.run()
        passed += 1
        print("  ok  \(test.name)")
    } catch {
        failed.append(test.name)
        print("fail  \(test.name)\n        \(error)")
    }
}

print("\n\(passed)/\(tests.count) passed")
if !failed.isEmpty {
    print("failed: \(failed.joined(separator: ", "))")
    exit(1)
}
