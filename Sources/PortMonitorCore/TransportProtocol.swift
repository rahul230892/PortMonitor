import Foundation

/// Transport protocol that a monitored socket is using.
public enum TransportProtocol: String, CaseIterable, Sendable, Codable, Hashable {
    case tcp = "TCP"
    case udp = "UDP"
}
