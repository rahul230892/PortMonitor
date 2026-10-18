import Foundation

/// Parses machine-readable `lsof -F` output into ``PortInfo`` values.
///
/// This is deliberately a pure function so it can be unit tested without ever
/// invoking `lsof` on the host.
public enum LsofParser {

    /// Parses `lsof -F pcuftn` output.
    ///
    /// - Parameters:
    ///   - output: Raw stdout from `lsof -F pcuftn`.
    ///   - transport: Transport protocol the query was scoped to.
    ///   - defaultState: State to apply when the entry does not carry one
    ///     (e.g. `LISTEN` for a `-sTCP:LISTEN` query).
    public static func parse(
        _ output: String,
        transport: TransportProtocol,
        defaultState: String? = nil
    ) -> [PortInfo] {
        var results: [PortInfo] = []

        var pid = 0
        var command = ""
        var uid = 0
        var fd = 0

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                pid = Int(value) ?? 0
                command = ""
                uid = 0
                fd = 0
            case "c":
                command = value
            case "u":
                uid = Int(value) ?? 0
            case "f":
                fd = Int(value) ?? 0
            case "n":
                guard pid != 0, let parsed = parseName(value) else { continue }
                results.append(
                    PortInfo(
                        port: parsed.port,
                        host: parsed.host,
                        processName: command.isEmpty ? "pid \(pid)" : command,
                        pid: pid,
                        userID: uid,
                        fd: fd,
                        transport: transport,
                        state: parsed.state ?? defaultState
                    )
                )
            default:
                continue
            }
        }

        return results
    }

    /// Splits an `lsof` name field into host, port and optional state.
    ///
    /// Handles `*:7000`, `127.0.0.1:5432`, `[::1]:8080`, unbound `*:*`, and
    /// connected sockets such as `127.0.0.1:5000->1.2.3.4:80 (ESTABLISHED)`.
    static func parseName(_ raw: String) -> (host: String, port: Int, state: String?)? {
        var name = raw.trimmingCharacters(in: .whitespaces)
        var state: String?

        // Trailing " (STATE)" suffix, e.g. "(LISTEN)".
        if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
            let close = name.index(before: name.endIndex)
            state = String(name[name.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }

        // For connected sockets keep only the local side.
        if let arrow = name.range(of: "->") {
            name = String(name[..<arrow.lowerBound])
        }

        guard let colon = name.lastIndex(of: ":") else { return nil }
        let hostPart = String(name[..<colon])
        let portPart = String(name[name.index(after: colon)...])

        // `*:*` (unbound) and any non-numeric port are not useful here.
        guard let port = Int(portPart), (0...65535).contains(port) else { return nil }

        var host = hostPart
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.isEmpty { host = "*" }

        return (host, port, state)
    }
}
