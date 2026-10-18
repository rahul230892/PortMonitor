import Foundation

/// Runs a helper executable and returns its stdout as text.
///
/// Shared by the providers so process handling lives in one place. Intentionally
/// internal: it is an implementation detail of the backends.
enum Subprocess {
    /// - Parameters:
    ///   - executablePath: Absolute path to the binary.
    ///   - arguments: Arguments to pass.
    ///   - allowingStatus: Exit codes treated as success. Defaults to `{0}`;
    ///     `lsof` uses `{0, 1}` because it returns 1 when nothing matched.
    static func run(
        _ executablePath: String,
        _ arguments: [String],
        allowingStatus: Set<Int32> = [0]
    ) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw PortProviderError.toolNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if !allowingStatus.contains(process.terminationStatus) {
            let message = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PortProviderError.failed(
                status: process.terminationStatus,
                message: message
            )
        }

        return String(decoding: outData, as: UTF8.self)
    }
}
