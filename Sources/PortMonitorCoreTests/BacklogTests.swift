import Foundation
import PortMonitorCore

// Tests for the backlog features: filter presets, the refresh differ,
// per-process grouping, traffic rates, the nettop parser and export.

// MARK: - Fixtures

func makePort(
    _ port: Int,
    _ transport: TransportProtocol = .tcp,
    host: String = "*",
    process: String = "demo",
    pid: Int = 100,
    fd: Int = 3,
    uid: Int = 501,
    state: String? = "LISTEN"
) -> PortInfo {
    PortInfo(
        port: port, host: host, processName: process,
        pid: pid, userID: uid, fd: fd, transport: transport, state: state
    )
}

// MARK: - PortFilter / presets

func testPresetAllKeepsEverything() throws {
    let ports = [
        makePort(80, .tcp, process: "nginx"),
        makePort(5353, .udp, process: "dns-sd", state: nil)
    ]

    try expectEqual(PortFilter.apply(ports, preset: .all).count, 2, "all keeps everything")
}

func testPresetsNarrowByProtocolAndPortBand() throws {
    let ports = [
        makePort(22, .tcp, process: "sshd"),
        makePort(443, .tcp, process: "nginx"),
        makePort(8080, .tcp, process: "node"),
        makePort(5353, .udp, process: "dns-sd", state: nil),
        makePort(68, .udp, process: "dhcp", state: nil)
    ]

    try expectEqual(
        PortFilter.apply(ports, preset: .tcp).map(\.port), [22, 443, 8080], "TCP only"
    )
    try expectEqual(
        PortFilter.apply(ports, preset: .udp).map(\.port), [5353, 68], "UDP only"
    )
    try expectEqual(
        PortFilter.apply(ports, preset: .privileged).map(\.port), [22, 443, 68], "privileged"
    )
    try expectEqual(
        PortFilter.apply(ports, preset: .unprivileged).map(\.port), [8080, 5353], "unprivileged"
    )
}

func testListeningPresetDropsNonListeners() throws {
    let ports = [
        makePort(80, .tcp, state: "LISTEN"),
        makePort(5000, .tcp, state: "ESTABLISHED"),
        makePort(5353, .udp, state: nil)
    ]

    try expectEqual(
        PortFilter.apply(ports, preset: .listening).map(\.port), [80], "listening only"
    )
}

func testQueryMatchesNamePortPidHostProtoAndState() throws {
    let ports = [
        makePort(8080, .tcp, host: "127.0.0.1", process: "node", pid: 4242, state: "LISTEN"),
        makePort(5432, .tcp, host: "*", process: "postgres", pid: 77, state: "LISTEN")
    ]

    try expectEqual(PortFilter.apply(ports, query: "node").map(\.port), [8080], "by name")
    try expectEqual(PortFilter.apply(ports, query: "5432").map(\.port), [5432], "by port")
    try expectEqual(PortFilter.apply(ports, query: "4242").map(\.port), [8080], "by pid")
    try expectEqual(PortFilter.apply(ports, query: "127.0.0.1").map(\.port), [8080], "by host")
    try expectEqual(PortFilter.apply(ports, query: "listen").count, 2, "by state, case-insensitive")
    try expectEqual(PortFilter.apply(ports, query: "  POSTGRES ").map(\.port), [5432], "trimmed + lowercased")
}

func testQueryAndPresetCompose() throws {
    let ports = [
        makePort(5353, .udp, process: "dns-sd", state: nil),
        makePort(5354, .udp, process: "other", state: nil),
        makePort(5355, .tcp, process: "dns-sd")
    ]

    let filtered = PortFilter.apply(ports, query: "dns", preset: .udp)
    try expectEqual(filtered.map(\.port), [5353], "preset and query both applied")
}

// MARK: - PortListDiffer

func testFirstSampleIsInitialLoadAndHighlightsNothing() throws {
    var differ = PortListDiffer()
    let update = differ.apply([makePort(80), makePort(443)])

    try expect(update.isInitialLoad, "first sample is the initial load")
    try expectEqual(update.added.count, 2, "all sockets reported as added for bookkeeping")
    try expect(update.addedIDs.isEmpty, "nothing is highlighted on first load")
    try expect(update.removed.isEmpty, "nothing removed")
}

func testDifferReportsAddedAndRemovedSockets() throws {
    var differ = PortListDiffer()
    let a = makePort(80, process: "nginx")
    let b = makePort(443, process: "nginx")

    differ.apply([a])

    let update = differ.apply([b])
    try expect(!update.isInitialLoad, "not the initial load")
    try expectEqual(update.added.map(\.port), [443], "new port detected")
    try expectEqual(update.removed.map(\.port), [80], "closed port detected")
    try expectEqual(update.addedIDs, [b.id], "highlight set carries the new socket id")
}

func testDifferIsStableWhenNothingChanges() throws {
    var differ = PortListDiffer()
    let ports = [makePort(80), makePort(443)]

    differ.apply(ports)
    let update = differ.apply(ports)

    try expect(update.isEmpty, "no changes between identical samples")
    try expect(update.addedIDs.isEmpty, "no highlights")
}

func testDifferResetMakesNextSampleTheInitialLoadAgain() throws {
    var differ = PortListDiffer()
    differ.apply([makePort(80)])
    differ.reset()

    let update = differ.apply([makePort(443)])
    try expect(update.isInitialLoad, "reset restores the first-load behaviour")
    try expect(update.addedIDs.isEmpty, "reset suppresses highlighting")
}

// MARK: - ProcessGrouping

func testGroupsSocketsByOwningProcess() throws {
    let ports = [
        makePort(8080, process: "node", pid: 10),
        makePort(3000, process: "node", pid: 10),
        makePort(5432, process: "postgres", pid: 20),
        makePort(53, .udp, process: "dns-sd", pid: 30, state: nil)
    ]

    let groups = ProcessGrouping.groups(from: ports)

    try expectEqual(groups.map(\.processName), ["dns-sd", "node", "postgres"], "sorted by name")
    let node = try firstGroup(groups, named: "node")
    try expectEqual(node.pid, 10, "node pid")
    try expectEqual(node.ports.map(\.port), [3000, 8080], "sockets sorted by port inside the group")
    try expectEqual(node.portCount, 2, "port count")
    try expectEqual(node.listeningCount, 2, "listening count")
    try expectEqual(node.portsSummary, "3000/TCP, 8080/TCP", "summary")
}

func testGroupingKeepsSameNameWithDifferentPidsApart() throws {
    let ports = [
        makePort(1, process: "helper", pid: 1),
        makePort(2, process: "helper", pid: 2)
    ]

    let groups = ProcessGrouping.groups(from: ports)
    try expectEqual(groups.count, 2, "one group per pid")
    try expectEqual(groups.map(\.id), [1, 2], "groups ordered by pid when names match")
}

// MARK: - Traffic

func testRatesAreComputedFromByteDeltas() throws {
    let before = [ProcessTraffic(pid: 7, name: "node", bytesIn: 1_000, bytesOut: 500)]
    let after = [ProcessTraffic(pid: 7, name: "node", bytesIn: 3_000, bytesOut: 1_500)]

    let rates = TrafficRateCalculator.rates(previous: before, current: after, interval: 2)

    let rate = try expectRate(rates, for: 7)
    try expectEqual(rate.bytesInPerSecond, 1_000, "3,000-1,000 over 2s")
    try expectEqual(rate.bytesOutPerSecond, 500, "1,500-500 over 2s")
}

func testRatesSkipUnknownPIDsAndZeroTraffic() throws {
    let before = [ProcessTraffic(pid: 1, name: "a", bytesIn: 10, bytesOut: 10)]
    let after = [
        ProcessTraffic(pid: 1, name: "a", bytesIn: 10, bytesOut: 10), // idle
        ProcessTraffic(pid: 2, name: "b", bytesIn: 900, bytesOut: 900) // started between samples
    ]

    let rates = TrafficRateCalculator.rates(previous: before, current: after, interval: 1)

    try expect(rates[1] == nil, "idle process omitted")
    try expect(rates[2] == nil, "unknown pid skipped (would spike)")
    try expect(rates.isEmpty, "nothing to report")
}

func testRatesClampCounterResetsToZero() throws {
    let before = [ProcessTraffic(pid: 1, name: "a", bytesIn: 10_000, bytesOut: 10_000)]
    let after = [ProcessTraffic(pid: 1, name: "a", bytesIn: 100, bytesOut: 100)]

    let rates = TrafficRateCalculator.rates(previous: before, current: after, interval: 1)
    try expect(rates.isEmpty, "a restarted process reports no bogus throughput")
}

func testRatesRequirePositiveInterval() throws {
    let sample = [ProcessTraffic(pid: 1, name: "a", bytesIn: 1, bytesOut: 1)]
    let rates = TrafficRateCalculator.rates(previous: sample, current: sample, interval: 0)
    try expect(rates.isEmpty, "a non-positive interval yields no rates")
}

func testRateFormatting() throws {
    try expectEqual(RateFormat.string(bytesPerSecond: 0), "0 B/s", "zero")
    try expectEqual(RateFormat.string(bytesPerSecond: 999), "999 B/s", "bytes")
    try expectEqual(RateFormat.string(bytesPerSecond: 1_500), "1.5 KB/s", "kilobytes")
    try expectEqual(RateFormat.string(bytesPerSecond: 2_500_000), "2.5 MB/s", "megabytes")
    try expectEqual(RateFormat.string(bytesPerSecond: -5), "0 B/s", "negatives clamp")
    try expectEqual(RateFormat.compact(nil), "—", "no rate")
}

// MARK: - NettopParser

private let nettopFixture = """
time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
05:57:57.200096,launchd.1,,,0,0,0,0,0,,,,,,,,,,,,
05:57:57.200100,com.apple.WebKit.4321,,,1200,3400,0,0,0,,,,,,,,,,,,
05:57:57.200106,apsd.140,,,5561,12921,0,0,0,,,,,,,,,,,,
garbage row with too few fields
05:57:57.200109,broken.name,,,notanumber,12,0,0,0,,,,,,,,,,,,
"""

func testParsesNettopCSV() throws {
    let traffic = NettopParser.parse(nettopFixture)

    try expectEqual(traffic.count, 3, "three valid rows parsed")
    try expectEqual(traffic.map(\.pid), [1, 4321, 140], "pids in order")
    try expectEqual(traffic[0].name, "launchd", "name without pid")
    try expectEqual(traffic[0].bytesIn, 0, "bytes in")
    try expectEqual(traffic[1].name, "com.apple.WebKit", "dots preserved in process name")
    try expectEqual(traffic[2].bytesOut, 12_921, "bytes out")
}

func testNettopProviderUsesItsRunner() throws {
    let provider = NettopTrafficProvider { args in
        try expectEqual(args, ["-P", "-L", "1", "-n", "-x"], "nettop arguments")
        return nettopFixture
    }

    let traffic = try provider.sample()
    try expectEqual(traffic.count, 3, "stubbed sample parsed")
}

func testNettopProviderReportsMissingTool() throws {
    let provider = NettopTrafficProvider(executablePath: "/nonexistent/nettop")

    try expectThrows("missing nettop should throw", matcher: { error in
        if case PortProviderError.toolNotFound = error { return true }
        return false
    }) {
        _ = try provider.sample()
    }
}

func testRealNettopRunsOnThisHost() throws {
    // nettop should at least run and return parseable rows on a normal Mac.
    let traffic = try NettopTrafficProvider().sample()
    try skipIf(traffic.isEmpty, "nettop reported no per-process rows on this host")
    try expect(traffic.allSatisfy { $0.pid > 0 }, "every row has a pid")
}

// MARK: - Export

func testCSVHasHeaderAndEscapesFields() throws {
    let ports = [
        makePort(8080, .tcp, host: "127.0.0.1", process: "Code Helper, Inc.", pid: 9, state: "LISTEN"),
        makePort(5353, .udp, process: "dns-sd", pid: 10, state: nil)
    ]

    let csv = PortExport.csv(ports)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

    try expectEqual(lines.count, 3, "header plus two rows")
    try expectEqual(lines[0], "Port,Protocol,Process,PID,User,Address,State", "header")
    try expect(lines[1].contains("\"Code Helper, Inc.\""), "comma-containing field is quoted")
    try expect(lines[2].hasSuffix("dns-sd,10,501,*,"), "empty state renders as an empty field")
    try expect(csv.hasSuffix("\n"), "file ends with a newline")
}

func testCSVEscapesEmbeddedQuotes() throws {
    try expectEqual(PortExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"", "quotes doubled")
    try expectEqual(PortExport.escape("plain"), "plain", "plain field untouched")
    try expectEqual(PortExport.escape("two\nlines"), "\"two\nlines\"", "newline forces quoting")
}

func testJSONExportRoundTrips() throws {
    let ports = [
        makePort(80, .tcp, host: "::1", process: "nginx", pid: 5),
        makePort(5353, .udp, process: "dns-sd", pid: 6, state: nil)
    ]

    let data = try PortExport.data(ports, format: .json)
    let decoded = try JSONDecoder().decode([PortInfo].self, from: data)

    try expectEqual(decoded, ports, "JSON round-trips the port list")
}

// MARK: - Helpers

private func firstGroup(_ groups: [ProcessGroup], named name: String) throws -> ProcessGroup {
    guard let match = groups.first(where: { $0.processName == name }) else {
        throw TestFailure(description: "no group named \(name)")
    }
    return match
}

private func expectRate(_ rates: [Int: TrafficRate], for pid: Int) throws -> TrafficRate {
    guard let rate = rates[pid] else {
        throw TestFailure(description: "no rate for pid \(pid)")
    }
    return rate
}
