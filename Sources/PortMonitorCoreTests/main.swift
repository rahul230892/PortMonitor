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
    ("identifier is stable and distinguishes sockets", testIdentifierIsStableAndDistinguishesSockets),

    // Filter presets
    ("preset 'all' keeps everything", testPresetAllKeepsEverything),
    ("presets narrow by protocol and port band", testPresetsNarrowByProtocolAndPortBand),
    ("listening preset drops non-listeners", testListeningPresetDropsNonListeners),
    ("query matches name, port, pid, host, proto and state", testQueryMatchesNamePortPidHostProtoAndState),
    ("query and preset compose", testQueryAndPresetCompose),

    // Refresh differ
    ("first sample is the initial load and highlights nothing", testFirstSampleIsInitialLoadAndHighlightsNothing),
    ("differ reports added and removed sockets", testDifferReportsAddedAndRemovedSockets),
    ("differ is stable when nothing changes", testDifferIsStableWhenNothingChanges),
    ("differ reset restores first-load behaviour", testDifferResetMakesNextSampleTheInitialLoadAgain),

    // Per-process grouping
    ("groups sockets by owning process", testGroupsSocketsByOwningProcess),
    ("grouping keeps same-named processes with different pids apart", testGroupingKeepsSameNameWithDifferentPidsApart),

    // Traffic rates
    ("rates are computed from byte deltas", testRatesAreComputedFromByteDeltas),
    ("rates skip unknown pids and zero traffic", testRatesSkipUnknownPIDsAndZeroTraffic),
    ("rates clamp counter resets to zero", testRatesClampCounterResetsToZero),
    ("rates require a positive interval", testRatesRequirePositiveInterval),
    ("rate formatting", testRateFormatting),

    // nettop
    ("parses nettop CSV", testParsesNettopCSV),
    ("nettop provider uses its runner", testNettopProviderUsesItsRunner),
    ("nettop provider reports a missing tool", testNettopProviderReportsMissingTool),
    ("real nettop runs on this host", testRealNettopRunsOnThisHost),

    // Export
    ("CSV has a header and escapes fields", testCSVHasHeaderAndEscapesFields),
    ("CSV escapes embedded quotes", testCSVEscapesEmbeddedQuotes),
    ("JSON export round-trips", testJSONExportRoundTrips)
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
