import Foundation

/// A single open network port owned by a local process.
public struct PortInfo: Identifiable, Hashable, Sendable, Codable {
    /// Stable identifier for the underlying socket (protocol + PID + file descriptor + port).
    public let id: String
    public let port: Int
    /// Local address the socket is bound to, e.g. `*`, `127.0.0.1`, or `::1`.
    public let host: String
    public let processName: String
    public let pid: Int
    /// Numeric user id reported by `lsof`.
    public let userID: Int
    /// File descriptor number inside the owning process.
    public let fd: Int
    public let transport: TransportProtocol
    /// Socket state such as `LISTEN` or `ESTABLISHED`, when known.
    public let state: String?

    public init(
        port: Int,
        host: String,
        processName: String,
        pid: Int,
        userID: Int,
        fd: Int,
        transport: TransportProtocol,
        state: String?
    ) {
        self.id = "\(transport.rawValue)-\(pid)-\(fd)-\(port)"
        self.port = port
        self.host = host
        self.processName = processName
        self.pid = pid
        self.userID = userID
        self.fd = fd
        self.transport = transport
        self.state = state
    }

    /// Whether this socket is accepting inbound connections.
    public var isListening: Bool {
        state?.uppercased() == "LISTEN"
    }
}
