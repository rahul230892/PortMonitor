import Foundation
import PortMonitorCore

/// A `PortProviding` stub backed by an arbitrary closure.
struct StubProvider: PortProviding {
    private let run: @Sendable () throws -> [PortInfo]

    init(_ run: @escaping @Sendable () throws -> [PortInfo]) {
        self.run = run
    }

    func currentPorts() throws -> [PortInfo] {
        try run()
    }
}

/// A failure raised by a test expectation.
struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

/// Raised when a test cannot run meaningfully on the current host.
///
/// Used by the integration tests that compare real backends: on a machine (or a
/// CI runner) where a backend legitimately sees no sockets, there is nothing to
/// compare and the test should be reported as skipped rather than failed.
struct TestSkipped: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Skips the current test when `condition` is true.
func skipIf(
    _ condition: Bool,
    _ reason: @autoclosure () -> String = "not applicable on this host"
) throws {
    if condition {
        throw TestSkipped(reason())
    }
}

private func location(_ file: StaticString, _ line: UInt) -> String {
    "\(URL(fileURLWithPath: file.description).lastPathComponent):\(line)"
}

/// Asserts that `condition` is true.
func expect(
    _ condition: Bool,
    _ message: String = "condition was false",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure(description: "\(message) [\(location(file, line))]")
    }
}

/// Asserts that `lhs == rhs`.
func expectEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    guard lhs == rhs else {
        let label = message.isEmpty ? "values differ" : message
        throw TestFailure(description: "\(label): expected \(rhs), got \(lhs) [\(location(file, line))]")
    }
}

/// Asserts that `value` is `nil`.
func expectNil<T>(
    _ value: T?,
    _ message: String = "expected nil",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    guard value == nil else {
        throw TestFailure(description: "\(message): got \(String(describing: value)) [\(location(file, line))]")
    }
}

/// Asserts that `body` throws; if `matcher` is supplied it must also match.
func expectThrows(
    _ message: String = "expected an error to be thrown",
    file: StaticString = #file,
    line: UInt = #line,
    matcher: ((Error) -> Bool)? = nil,
    _ body: () throws -> Void
) throws {
    do {
        try body()
    } catch {
        if let matcher, !matcher(error) {
            throw TestFailure(description: "\(message): unexpected error \(error) [\(location(file, line))]")
        }
        return
    }
    throw TestFailure(description: "\(message) [\(location(file, line))]")
}
