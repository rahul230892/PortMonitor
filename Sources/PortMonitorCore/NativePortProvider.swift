import Foundation
import CProcSockets

/// Reads open ports directly through libproc (`proc_listallpids` /
/// `proc_pidfdinfo`) instead of shelling out to `lsof`.
///
/// Like `lsof`, without elevated privileges this only sees processes owned by
/// the current user. Unlike `lsof` it does not spawn a subprocess.
public struct NativePortProvider: PortProviding {
    private static let ipProtoTCP: Int32 = 6
    private static let ipProtoUDP: Int32 = 17

    public init() {}

    public func currentPorts() throws -> [PortInfo] {
        let total = Int(cps_list_sockets(nil, 0))
        guard total >= 0 else {
            throw PortProviderError.failed(status: -1, message: "unable to enumerate processes")
        }
        guard total > 0 else { return [] }

        var buffer = [cps_socket_t](repeating: cps_socket_t(), count: total)
        let written = Int(buffer.withUnsafeMutableBufferPointer { pointer in
            cps_list_sockets(pointer.baseAddress, Int32(total))
        })
        guard written >= 0 else {
            throw PortProviderError.failed(status: -1, message: "unable to read sockets")
        }

        return buffer.prefix(min(written, total))
            .map(Self.makePortInfo)
            .sorted(by: Self.orderedBefore)
    }

    private static func makePortInfo(_ raw: cps_socket_t) -> PortInfo {
        var socket = raw
        let name = cString(of: &socket.name)
        let address = cString(of: &socket.address)
        let transport: TransportProtocol = socket.protocol == ipProtoUDP ? .udp : .tcp

        return PortInfo(
            port: Int(socket.port),
            host: address.isEmpty ? "*" : address,
            processName: name.isEmpty ? "pid \(socket.pid)" : name,
            pid: Int(socket.pid),
            userID: Int(socket.uid),
            fd: Int(socket.fd),
            transport: transport,
            state: transport == .tcp ? "LISTEN" : nil
        )
    }

    private static func orderedBefore(_ lhs: PortInfo, _ rhs: PortInfo) -> Bool {
        if lhs.port != rhs.port { return lhs.port < rhs.port }
        return lhs.transport.rawValue < rhs.transport.rawValue
    }
}

/// Reads a NUL-terminated C char buffer stored as a Swift tuple.
private func cString<T>(of value: inout T) -> String {
    withUnsafeBytes(of: &value) { raw in
        guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
        return String(cString: base)
    }
}
