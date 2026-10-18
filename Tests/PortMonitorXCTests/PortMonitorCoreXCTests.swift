import XCTest
import PortMonitorCore

// Opt-in XCTest mirror of `Sources/PortMonitorCoreTests`.
//
// Built only when PORTMONITOR_ENABLE_XCTEST=1 (see Package.swift and
// `make test-xctest`), because XCTest requires a full Xcode install.

private func makePort(
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

final class PortFilterTests: XCTestCase {
    private let ports = [
        makePort(22, .tcp, process: "sshd"),
        makePort(8080, .tcp, process: "node"),
        makePort(5353, .udp, process: "dns-sd", state: nil)
    ]

    func testPresets() {
        XCTAssertEqual(PortFilter.apply(ports, preset: .tcp).map(\.port), [22, 8080])
        XCTAssertEqual(PortFilter.apply(ports, preset: .udp).map(\.port), [5353])
        XCTAssertEqual(PortFilter.apply(ports, preset: .privileged).map(\.port), [22])
        XCTAssertEqual(PortFilter.apply(ports, preset: .unprivileged).map(\.port), [8080, 5353])
        XCTAssertEqual(PortFilter.apply(ports, preset: .all).count, 3)
    }

    func testQueryAndPresetCompose() {
        XCTAssertEqual(PortFilter.apply(ports, query: "node").map(\.port), [8080])
        XCTAssertEqual(PortFilter.apply(ports, query: "  NODE ").map(\.port), [8080])
        XCTAssertEqual(PortFilter.apply(ports, query: "dns", preset: .udp).map(\.port), [5353])
    }
}

final class PortListDifferTests: XCTestCase {
    func testInitialLoadHighlightsNothing() {
        var differ = PortListDiffer()
        let update = differ.apply([makePort(80), makePort(443)])

        XCTAssertTrue(update.isInitialLoad)
        XCTAssertTrue(update.addedIDs.isEmpty)
    }

    func testAddedAndRemoved() {
        var differ = PortListDiffer()
        differ.apply([makePort(80)])

        let update = differ.apply([makePort(443)])
        XCTAssertEqual(update.added.map(\.port), [443])
        XCTAssertEqual(update.removed.map(\.port), [80])
    }

    func testResetRestoresInitialLoad() {
        var differ = PortListDiffer()
        differ.apply([makePort(80)])
        differ.reset()

        XCTAssertTrue(differ.apply([makePort(443)]).isInitialLoad)
    }
}

final class ProcessGroupingTests: XCTestCase {
    func testGroupsByPID() {
        let groups = ProcessGrouping.groups(from: [
            makePort(8080, process: "node", pid: 10),
            makePort(3000, process: "node", pid: 10),
            makePort(5432, process: "postgres", pid: 20)
        ])

        XCTAssertEqual(groups.map(\.processName), ["node", "postgres"])
        XCTAssertEqual(groups[0].ports.map(\.port), [3000, 8080])
        XCTAssertEqual(groups[0].listeningCount, 2)
    }
}

final class TrafficTests: XCTestCase {
    func testRatesFromDeltas() {
        let rates = TrafficRateCalculator.rates(
            previous: [ProcessTraffic(pid: 7, name: "node", bytesIn: 1_000, bytesOut: 500)],
            current: [ProcessTraffic(pid: 7, name: "node", bytesIn: 3_000, bytesOut: 1_500)],
            interval: 2
        )

        XCTAssertEqual(rates[7]?.bytesInPerSecond ?? -1, 1_000.0)
        XCTAssertEqual(rates[7]?.bytesOutPerSecond ?? -1, 500.0)
    }

    func testCounterResetIsClamped() {
        let rates = TrafficRateCalculator.rates(
            previous: [ProcessTraffic(pid: 1, name: "a", bytesIn: 10_000, bytesOut: 10_000)],
            current: [ProcessTraffic(pid: 1, name: "a", bytesIn: 100, bytesOut: 100)],
            interval: 1
        )
        XCTAssertTrue(rates.isEmpty)
    }

    func testRateFormatting() {
        XCTAssertEqual(RateFormat.string(bytesPerSecond: 1_500), "1.5 KB/s")
        XCTAssertEqual(RateFormat.string(bytesPerSecond: 999), "999 B/s")
        XCTAssertEqual(RateFormat.compact(nil), "—")
    }
}

private let nettopFixtureCSV = """
time,,interface,state,bytes_in,bytes_out,rx_dupe
05:57:57.200096,launchd.1,,,0,0,0
05:57:57.200100,com.apple.WebKit.4321,,,1200,3400,0
"""

final class NettopParserTests: XCTestCase {
    func testParsesRowsAndPreservesDottedNames() {
        let traffic = NettopParser.parse(nettopFixtureCSV)

        XCTAssertEqual(traffic.count, 2)
        XCTAssertEqual(traffic[0].pid, 1)
        XCTAssertEqual(traffic[1].name, "com.apple.WebKit")
        XCTAssertEqual(traffic[1].bytesOut, 3_400)
    }

    func testStubbedProvider() throws {
        let provider = NettopTrafficProvider { _ in nettopFixtureCSV }
        XCTAssertEqual(try provider.sample().count, 2)
    }
}

final class PortExportTests: XCTestCase {
    func testCSVHeaderAndEscaping() {
        let csv = PortExport.csv([makePort(8080, process: "Code Helper, Inc.")])
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines[0], "Port,Protocol,Process,PID,User,Address,State")
        XCTAssertTrue(lines[1].contains("\"Code Helper, Inc.\""))
        XCTAssertEqual(PortExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testJSONRoundTrips() throws {
        let ports = [makePort(80, host: "::1", process: "nginx", pid: 5)]
        let data = try PortExport.data(ports, format: .json)

        XCTAssertEqual(try JSONDecoder().decode([PortInfo].self, from: data), ports)
    }
}

final class ProviderTests: XCTestCase {
    func testFallbackUsesFirstNonEmptyProvider() throws {
        let ports = try FallbackPortProvider([
            StubProvider { [] },
            StubProvider { [makePort(3333)] }
        ]).currentPorts()

        XCTAssertEqual(ports.map(\.port), [3333])
    }

    func testNativeAndLsofRunOnThisHost() throws {
        let native = try NativePortProvider().currentPorts()
        let lsof = try LsofPortProvider().currentPorts()

        // A CI runner may legitimately have no sockets visible to the
        // unprivileged user; skip rather than report a false failure.
        try XCTSkipIf(native.isEmpty, "native backend saw no sockets on this host")
        try XCTSkipIf(lsof.isEmpty, "lsof saw no sockets on this host")

        XCTAssertTrue(native.allSatisfy { (0...65535).contains($0.port) })
        XCTAssertEqual(native.map(\.port), native.map(\.port).sorted())

        // When both backends see TCP listeners, they should broadly agree.
        let nativeTCP = Set(native.filter { $0.transport == .tcp }.map(\.port))
        let lsofTCP = Set(lsof.filter { $0.transport == .tcp }.map(\.port))
        try XCTSkipIf(nativeTCP.isEmpty || lsofTCP.isEmpty, "no TCP listeners visible")
        XCTAssertLessThanOrEqual(nativeTCP.subtracting(lsofTCP).count, 3)
        XCTAssertLessThanOrEqual(lsofTCP.subtracting(nativeTCP).count, 3)
    }
}

private struct StubProvider: PortProviding {
    private let run: @Sendable () throws -> [PortInfo]

    init(_ run: @escaping @Sendable () throws -> [PortInfo]) {
        self.run = run
    }

    func currentPorts() throws -> [PortInfo] { try run() }
}
