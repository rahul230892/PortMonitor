import Foundation

public enum PortProviderError: LocalizedError {
    case toolNotFound(String)
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let path):
            return "Required tool not found at \(path)."
        case .failed(let status, let message):
            let detail = message.isEmpty ? "no output" : message
            return "lsof exited with status \(status): \(detail)"
        }
    }
}

/// Reads open ports by invoking `lsof` in machine-readable mode.
///
/// Note: without elevated privileges `lsof` can only report details for
/// processes owned by the current user, so system daemons may be missing.
public struct LsofPortProvider: PortProviding {
    private let executablePath: String
    private let run: @Sendable ([String]) throws -> String

    /// - Parameter runner: Testing seam. When `nil`, the real `lsof` binary is used.
    public init(
        executablePath: String = "/usr/sbin/lsof",
        runner: (@Sendable ([String]) throws -> String)? = nil
    ) {
        self.executablePath = executablePath
        if let runner {
            self.run = runner
        } else {
            // lsof returns 1 when nothing matched; that is not an error for us.
            self.run = { args in try Subprocess.run(executablePath, args, allowingStatus: [0, 1]) }
        }
    }

    public func currentPorts() throws -> [PortInfo] {
        let tcp = LsofParser.parse(
            try run(["-nP", "-F", "pcuftn", "-iTCP", "-sTCP:LISTEN"]),
            transport: .tcp,
            defaultState: "LISTEN"
        )
        let udp = LsofParser.parse(
            try run(["-nP", "-F", "pcuftn", "-iUDP"]),
            transport: .udp
        )

        return (tcp + udp).sorted { lhs, rhs in
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.transport.rawValue < rhs.transport.rawValue
        }
    }
}
