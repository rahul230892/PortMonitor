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
            self.run = { args in try Self.runLsof(executablePath, args) }
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

    private static func runLsof(_ path: String, _ args: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw PortProviderError.toolNotFound(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // lsof returns 1 when nothing matches; that is not an error for us.
        if process.terminationStatus != 0 && process.terminationStatus != 1 {
            let message = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PortProviderError.failed(status: process.terminationStatus, message: message)
        }

        return String(decoding: outData, as: UTF8.self)
    }
}
