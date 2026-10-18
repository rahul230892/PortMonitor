import Foundation
import PortMonitorCore

// MARK: - LsofParser

private let tcpListingFixture = """
p497
cControlCenter
u501
f9
tIPv4
n*:7000
f10
tIPv6
n*:7000
p1796
cCode Helper
u501
f29
tIPv4
n127.0.0.1:49161
"""

func testParsesListeningTCPEntriesAndAppliesDefaultState() throws {
    let ports = LsofParser.parse(tcpListingFixture, transport: .tcp, defaultState: "LISTEN")

    try expectEqual(ports.count, 3, "parsed entry count")
    try expectEqual(ports.map(\.port), [7000, 7000, 49161], "ports")
    try expect(ports.allSatisfy { $0.transport == .tcp }, "all entries are TCP")
    try expect(ports.allSatisfy(\.isListening), "all entries marked LISTEN")
}

func testPreservesCommandNamesContainingSpaces() throws {
    let output = """
    p1797
    cCode Helper (Plugin)
    u501
    f32
    tIPv4
    n127.0.0.1:49160
    """

    let ports = LsofParser.parse(output, transport: .tcp, defaultState: "LISTEN")
    let first = try expectFirst(ports)

    try expectEqual(first.processName, "Code Helper (Plugin)", "process name")
    try expectEqual(first.pid, 1797, "pid")
    try expectEqual(first.userID, 501, "uid")
    try expectEqual(first.fd, 32, "fd")
}

func testSkipsUnboundUDPEntries() throws {
    let output = """
    p451
    cidentityservicesd
    u501
    f7
    tIPv4
    n*:*
    p476
    csharingd
    u502
    f4
    tIPv4
    n*:*
    p671
    cdns-sd
    u503
    f35
    tIPv4
    n*:5353
    """

    let ports = LsofParser.parse(output, transport: .udp)
    let first = try expectFirst(ports)

    try expectEqual(ports.count, 1, "only bound UDP sockets are kept")
    try expectEqual(first.port, 5353, "port")
    try expectEqual(first.processName, "dns-sd", "process name")
    try expectNil(first.state, "no state for UDP")
    try expect(!first.isListening, "UDP socket is not listening")
}

func testUsesLocalSideAndStateForConnectedSockets() throws {
    let output = """
    p1234
    cdemo
    u501
    f3
    tIPv4
    n127.0.0.1:5000->1.2.3.4:80 (ESTABLISHED)
    """

    let first = try expectFirst(LsofParser.parse(output, transport: .tcp))

    try expectEqual(first.host, "127.0.0.1", "local host")
    try expectEqual(first.port, 5000, "local port")
    try expectEqual(first.state, Optional("ESTABLISHED"), "state")
    try expect(!first.isListening, "established socket is not listening")
}

func testUnwrapsIPv6Host() throws {
    let output = """
    p1
    cdemo
    u0
    f3
    tIPv6
    n[::1]:8080
    """

    let first = try expectFirst(LsofParser.parse(output, transport: .tcp, defaultState: "LISTEN"))

    try expectEqual(first.host, "::1", "ipv6 host")
    try expectEqual(first.port, 8080, "port")
}

func testIgnoresMalformedAndIrrelevantLines() throws {
    let output = """
    p1
    cdemo
    u0
    f3
    tIPv4
    nnot-a-socket
    junk line without a field

    p2
    cother
    u0
    f4
    tIPv4
    n*:notaport
    """

    try expect(LsofParser.parse(output, transport: .tcp).isEmpty, "malformed entries are ignored")
}

// MARK: - LsofPortProvider

private let providerTCPFixture = """
p497
cControlCenter
u501
f9
tIPv4
n*:7000
p9612
cpostgres
u501
f7
tIPv4
n127.0.0.1:5432
"""

private let providerUDPFixture = """
p671
cdns-sd
u503
f35
tIPv4
n*:5353
"""

func testProviderCombinesTCPAndUDPAndSortsByPort() throws {
    let provider = LsofPortProvider { args in
        args.contains("-iTCP") ? providerTCPFixture : providerUDPFixture
    }

    let ports = try provider.currentPorts()

    try expectEqual(ports.map(\.port), [5353, 5432, 7000], "sorted combined ports")
    try expect(ports.contains { $0.transport == .tcp }, "contains TCP entries")
    try expect(ports.contains { $0.transport == .udp }, "contains UDP entries")
    try expect(ports.first { $0.transport == .tcp }?.isListening == true, "TCP entries listen")
}

func testProviderReportsMissingTool() throws {
    let provider = LsofPortProvider(executablePath: "/nonexistent/lsof")

    try expectThrows("missing lsof should throw", matcher: { error in
        if case PortProviderError.toolNotFound = error { return true }
        return false
    }) {
        _ = try provider.currentPorts()
    }
}

func testRealProviderRunsOnThisHost() throws {
    let ports = try LsofPortProvider().currentPorts()

    try expectEqual(ports.map(\.port), ports.map(\.port).sorted(), "ports sorted")
    try expect(ports.allSatisfy { (0...65535).contains($0.port) }, "ports in range")
}

// MARK: - PortInfo

func testIdentifierIsStableAndDistinguishesSockets() throws {
    let base = PortInfo(
        port: 8080, host: "*", processName: "demo",
        pid: 1, userID: 0, fd: 3, transport: .tcp, state: "LISTEN"
    )
    let same = PortInfo(
        port: 8080, host: "*", processName: "demo",
        pid: 1, userID: 0, fd: 3, transport: .tcp, state: "LISTEN"
    )
    let differentFD = PortInfo(
        port: 8080, host: "*", processName: "demo",
        pid: 1, userID: 0, fd: 4, transport: .tcp, state: "LISTEN"
    )

    try expectEqual(base.id, same.id, "identical sockets share an id")
    try expect(base.id != differentFD.id, "different fds yield different ids")
    try expect(base.isListening, "LISTEN state detected")
}

// MARK: - Native / fallback providers

func testFallbackUsesFirstNonEmptyProvider() throws {
    let first = StubProvider { [stubPort(1111)] }
    let second = StubProvider { [stubPort(2222)] }

    let ports = try FallbackPortProvider([first, second]).currentPorts()

    try expectEqual(ports.map(\.port), [1111], "first provider wins")
}

func testFallbackSkipsEmptyAndErroringProviders() throws {
    let empty = StubProvider { [] }
    let failing = StubProvider { throw PortProviderError.failed(status: -1, message: "boom") }
    let working = StubProvider { [stubPort(3333)] }

    let ports = try FallbackPortProvider([empty, failing, working]).currentPorts()

    try expectEqual(ports.map(\.port), [3333], "falls through to working provider")
}

func testFallbackRethrowsWhenAllProvidersFail() throws {
    let provider = FallbackPortProvider([
        StubProvider { throw PortProviderError.failed(status: -1, message: "a") },
        StubProvider { throw PortProviderError.toolNotFound("/nope") }
    ])

    try expectThrows("all providers failed") {
        _ = try provider.currentPorts()
    }
}

func testNativeProviderReturnsSortedInRangePorts() throws {
    let ports = try NativePortProvider().currentPorts()

    try expect(!ports.isEmpty, "native provider found at least one socket")
    try expectEqual(ports.map(\.port), ports.map(\.port).sorted(), "native ports sorted")
    try expect(ports.allSatisfy { (0...65535).contains($0.port) }, "native ports in range")
    try expect(ports.allSatisfy { !$0.processName.isEmpty }, "every socket has a process name")
}

func testNativeAndLsofAgreeOnTcpListeners() throws {
    let native = Set(
        try NativePortProvider().currentPorts()
            .filter { $0.transport == .tcp }
            .map(\.port)
    )
    let lsof = Set(
        try LsofPortProvider().currentPorts()
            .filter { $0.transport == .tcp }
            .map(\.port)
    )

    try expect(!native.isEmpty, "native found TCP listeners")
    try expect(!lsof.isEmpty, "lsof found TCP listeners")

    // Allow a little slack for sockets opening/closing between the two calls.
    let onlyNative = native.subtracting(lsof)
    let onlyLsof = lsof.subtracting(native)
    try expect(onlyNative.count <= 3, "ports only native: \(onlyNative.sorted())")
    try expect(onlyLsof.count <= 3, "ports only lsof: \(onlyLsof.sorted())")
}

func testProviderKindBuildsExpectedProviders() throws {
    try expect(PortProviderKind.automatic.makeProvider() is FallbackPortProvider, "automatic is a fallback chain")
    try expect(PortProviderKind.native.makeProvider() is NativePortProvider, "native kind")
    try expect(PortProviderKind.lsof.makeProvider() is LsofPortProvider, "lsof kind")
    try expectEqual(PortProviderKind.allCases.count, 3, "three provider kinds")
}

// MARK: - Helpers

private func stubPort(_ value: Int) -> PortInfo {
    PortInfo(
        port: value, host: "*", processName: "stub",
        pid: 1, userID: 0, fd: 3, transport: .tcp, state: "LISTEN"
    )
}

private func expectFirst<T>(_ values: [T]) throws -> T {
    guard let first = values.first else {
        throw TestFailure(description: "expected at least one element, got none")
    }
    return first
}
