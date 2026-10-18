import Foundation

/// Serialises the current port list to a file format.
public enum PortExport {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case csv
        case json

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .csv: return "CSV"
            case .json: return "JSON"
            }
        }

        public var fileExtension: String { rawValue }
    }

    /// Serialises `ports` in the requested format.
    public static func data(_ ports: [PortInfo], format: Format) throws -> Data {
        switch format {
        case .csv:
            return Data(csv(ports).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(ports)
        }
    }

    /// The CSV column order, also used as the header row.
    public static let columns = ["Port", "Protocol", "Process", "PID", "User", "Address", "State"]

    /// Renders `ports` as RFC 4180 CSV with a header row.
    public static func csv(_ ports: [PortInfo]) -> String {
        var lines = [columns.joined(separator: ",")]

        for info in ports {
            let row = [
                String(info.port),
                info.transport.rawValue,
                info.processName,
                String(info.pid),
                String(info.userID),
                info.host,
                info.state ?? ""
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }

        // Trailing newline keeps the file POSIX-clean for downstream tools.
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quotes a field when it contains a delimiter, a quote or a newline.
    public static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")

        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
