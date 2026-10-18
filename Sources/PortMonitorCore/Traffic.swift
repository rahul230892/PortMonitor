import Foundation

/// Cumulative bytes attributed to one process by the kernel's network
/// accounting, as reported by `nettop`.
public struct ProcessTraffic: Equatable, Sendable {
    public let pid: Int
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(pid: Int, name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// A derived throughput for one process.
public struct TrafficRate: Equatable, Sendable {
    public let bytesInPerSecond: Double
    public let bytesOutPerSecond: Double

    public init(bytesInPerSecond: Double, bytesOutPerSecond: Double) {
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
    }
}

/// Reads a point-in-time snapshot of per-process traffic counters.
///
/// macOS does not expose per-socket byte counters through a public API, so
/// rates are attributed to the owning process (which is also how the grouped
/// view presents them).
public protocol TrafficSampling: Sendable {
    func sample() throws -> [ProcessTraffic]
}

/// Turns two counter snapshots into per-process throughput.
public enum TrafficRateCalculator {
    /// - Parameters:
    ///   - previous: The earlier counters.
    ///   - current: The later counters.
    ///   - interval: Seconds between the two samples; must be positive.
    /// - Returns: Rates for every PID with non-zero traffic, in bytes/second.
    ///
    /// A PID that is absent from `previous` (a process that started in between)
    /// is skipped rather than reported as a huge spike, and a counter that went
    /// backwards (process restarted) is clamped to zero.
    public static func rates(
        previous: [ProcessTraffic],
        current: [ProcessTraffic],
        interval: TimeInterval
    ) -> [Int: TrafficRate] {
        guard interval > 0 else { return [:] }

        var before: [Int: ProcessTraffic] = [:]
        for traffic in previous {
            before[traffic.pid] = traffic
        }

        var result: [Int: TrafficRate] = [:]
        for now in current {
            guard let old = before[now.pid] else { continue }

            let deltaIn = Double(now.bytesIn) - Double(old.bytesIn)
            let deltaOut = Double(now.bytesOut) - Double(old.bytesOut)
            let inRate = deltaIn > 0 ? deltaIn / interval : 0
            let outRate = deltaOut > 0 ? deltaOut / interval : 0

            if inRate > 0 || outRate > 0 {
                result[now.pid] = TrafficRate(bytesInPerSecond: inRate, bytesOutPerSecond: outRate)
            }
        }
        return result
    }
}

/// Deterministic byte/second formatting for the rate column.
public enum RateFormat {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Formats a bytes-per-second value, e.g. `1.5 KB/s`.
    public static func string(bytesPerSecond value: Double) -> String {
        let clamped = value.isFinite ? max(0, value) : 0
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]

        var scaled = clamped
        var unit = 0
        while scaled >= 1000, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }

        // No decimals for plain bytes, one for KB/MB, two from GB up.
        let decimals: Int
        switch unit {
        case 0: decimals = 0
        case 1, 2: decimals = 1
        default: decimals = 2
        }

        return String(format: "%.\(decimals)f %@", locale: posix, scaled, units[unit])
    }

    /// Compact `↓ 1.2 KB/s ↑ 3.4 KB/s` rendering, or `—` when idle.
    public static func compact(_ rate: TrafficRate?) -> String {
        guard let rate else { return "—" }
        return "↓ \(string(bytesPerSecond: rate.bytesInPerSecond)) ↑ \(string(bytesPerSecond: rate.bytesOutPerSecond))"
    }
}
