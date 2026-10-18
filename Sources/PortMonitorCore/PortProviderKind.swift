import Foundation

/// Tries each provider in order and returns the first non-empty result,
/// falling back to the next one on error. Guarantees the UI keeps working even
/// if a preferred backend is unavailable.
public struct FallbackPortProvider: PortProviding {
    private let providers: [PortProviding]

    public init(_ providers: [PortProviding]) {
        self.providers = providers
    }

    public func currentPorts() throws -> [PortInfo] {
        var lastError: Error?

        for provider in providers {
            do {
                let ports = try provider.currentPorts()
                if !ports.isEmpty {
                    return ports
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }
}

/// Which backend the app should use to read open ports.
public enum PortProviderKind: String, CaseIterable, Sendable, Identifiable {
    case automatic
    case native
    case lsof

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .native: return "Native (libproc)"
        case .lsof: return "lsof"
        }
    }

    /// Builds the provider for this selection.
    ///
    /// `automatic` prefers the native libproc backend but keeps `lsof` as a
    /// proven fallback so the app never regresses to showing nothing.
    public func makeProvider() -> PortProviding {
        switch self {
        case .automatic: return FallbackPortProvider([NativePortProvider(), LsofPortProvider()])
        case .native: return NativePortProvider()
        case .lsof: return LsofPortProvider()
        }
    }
}
