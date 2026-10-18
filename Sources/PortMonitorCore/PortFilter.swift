import Foundation

/// A canned, single-tap narrowing of the port list.
///
/// Presets compose with the free-text search: the search is applied first and
/// the preset is then used to further narrow the result.
public enum PortFilterPreset: String, CaseIterable, Sendable, Identifiable, Codable {
    case all
    case tcp
    case udp
    case listening
    case privileged
    case unprivileged

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All ports"
        case .tcp: return "TCP only"
        case .udp: return "UDP only"
        case .listening: return "Listening only"
        case .privileged: return "Privileged (<1024)"
        case .unprivileged: return "Unprivileged (>=1024)"
        }
    }

    /// Whether a socket survives this preset.
    public func matches(_ info: PortInfo) -> Bool {
        switch self {
        case .all: return true
        case .tcp: return info.transport == .tcp
        case .udp: return info.transport == .udp
        case .listening: return info.isListening
        case .privileged: return info.port < 1024
        case .unprivileged: return info.port >= 1024
        }
    }
}

/// Pure filtering shared by the UI and the tests.
public enum PortFilter {
    /// Narrows `ports` by a free-text `query` and a `preset`, preserving order.
    ///
    /// The query is matched case-insensitively against the process name, port,
    /// PID, address and transport.
    public static func apply(
        _ ports: [PortInfo],
        query: String = "",
        preset: PortFilterPreset = .all
    ) -> [PortInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return ports.filter { info in
            guard preset.matches(info) else { return false }
            guard !needle.isEmpty else { return true }

            return info.processName.lowercased().contains(needle)
                || String(info.port).contains(needle)
                || String(info.pid).contains(needle)
                || info.host.lowercased().contains(needle)
                || info.transport.rawValue.lowercased().contains(needle)
                || (info.state?.lowercased().contains(needle) ?? false)
        }
    }
}
