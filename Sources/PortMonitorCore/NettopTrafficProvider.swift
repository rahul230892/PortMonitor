import Foundation

/// Parses `nettop -P -L 1 -n -x` CSV output into per-process counters.
///
/// The CSV has a header row followed by one row per process:
///
/// ```
/// time,,interface,state,bytes_in,bytes_out,...
/// 05:57:57.200096,apsd.140,,,5561,12921,...
/// ```
///
/// Column 1 is `name.pid`, columns 4 and 5 are cumulative bytes in/out. Kept
/// pure so it can be tested without running `nettop`.
public enum NettopParser {
    public static func parse(_ csv: String) -> [ProcessTraffic] {
        var results: [ProcessTraffic] = []

        for (index, rawLine) in csv.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let line = String(rawLine)

            // Skip the header row.
            if index == 0, line.hasPrefix("time") { continue }

            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else { continue }

            guard let (name, pid) = parseNameAndPID(fields[1]) else { continue }
            guard
                let bytesIn = UInt64(fields[4].trimmingCharacters(in: .whitespaces)),
                let bytesOut = UInt64(fields[5].trimmingCharacters(in: .whitespaces))
            else { continue }

            results.append(ProcessTraffic(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut))
        }

        return results
    }

    /// Splits `mDNSResponder.183` into `("mDNSResponder", 183)`.
    ///
    /// The name may itself contain dots (`com.apple.WebKit.1234`), so only the
    /// final component is treated as the PID.
    static func parseNameAndPID(_ field: String) -> (name: String, pid: Int)? {
        guard let dot = field.lastIndex(of: ".") else { return nil }
        let name = String(field[..<dot])
        let pidPart = String(field[field.index(after: dot)...])
        guard let pid = Int(pidPart), pid > 0 else { return nil }
        return (name, pid)
    }
}

/// Samples per-process traffic with `nettop`.
///
/// `nettop` reports the kernel's per-process network accounting; no elevation is
/// required for the current user's processes.
public struct NettopTrafficProvider: TrafficSampling {
    private let executablePath: String
    private let run: @Sendable ([String]) throws -> String

    /// - Parameter runner: Testing seam. When `nil`, the real `nettop` binary is used.
    public init(
        executablePath: String = "/usr/bin/nettop",
        runner: (@Sendable ([String]) throws -> String)? = nil
    ) {
        self.executablePath = executablePath
        if let runner {
            self.run = runner
        } else {
            self.run = { args in try Subprocess.run(executablePath, args) }
        }
    }

    public func sample() throws -> [ProcessTraffic] {
        // -P per-process, -L 1 one CSV sample then exit, -n no DNS, -x raw numbers.
        let output = try run(["-P", "-L", "1", "-n", "-x"])
        return NettopParser.parse(output)
    }
}
