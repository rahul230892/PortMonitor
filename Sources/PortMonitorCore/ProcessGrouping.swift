import Foundation

/// All sockets belonging to a single process.
public struct ProcessGroup: Identifiable, Equatable, Sendable {
    public let pid: Int
    public let processName: String
    /// The process's sockets, sorted by port then protocol.
    public let ports: [PortInfo]

    /// Groups are keyed by PID: one row per process.
    public var id: Int { pid }

    public var portCount: Int { ports.count }
    public var listeningCount: Int { ports.filter(\.isListening).count }

    /// Distinct ports, ascending — handy for a compact summary line.
    public var portsSummary: String {
        ports.map { "\($0.port)/\($0.transport.rawValue)" }.joined(separator: ", ")
    }
}

/// Folds a flat socket list into per-process groups for the grouped table.
public enum ProcessGrouping {
    /// Groups `ports` by owning PID, then sorts groups by process name and PID
    /// and each group's sockets by port and protocol.
    public static func groups(from ports: [PortInfo]) -> [ProcessGroup] {
        let byPID = Dictionary(grouping: ports, by: \.pid)

        return byPID
            .map { pid, sockets in
                ProcessGroup(
                    pid: pid,
                    processName: sockets.first?.processName ?? "pid \(pid)",
                    ports: sockets.sorted(by: orderedBefore)
                )
            }
            .sorted { lhs, rhs in
                if lhs.processName != rhs.processName {
                    return lhs.processName.localizedStandardCompare(rhs.processName) == .orderedAscending
                }
                return lhs.pid < rhs.pid
            }
    }

    private static func orderedBefore(_ lhs: PortInfo, _ rhs: PortInfo) -> Bool {
        if lhs.port != rhs.port { return lhs.port < rhs.port }
        return lhs.transport.rawValue < rhs.transport.rawValue
    }
}
