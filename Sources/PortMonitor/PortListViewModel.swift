import Foundation
import Darwin
import PortMonitorCore

/// Raised when a process could not be terminated.
struct PortTerminationError: LocalizedError {
    let pid: Int
    let code: Int32

    var errorDescription: String? {
        let reason = String(cString: strerror(code))
        return "Could not terminate PID \(pid): \(reason)"
    }
}

/// Drives the port list UI: fetching, filtering, auto-refresh, change detection
/// and terminating the owner of a port.
@MainActor
final class PortListViewModel: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []
    @Published var searchText: String = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionError: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    /// Sockets that appeared since the previous refresh, for highlighting.
    @Published private(set) var newlyDiscovered: Set<String> = []

    var providerKind: PortProviderKind {
        didSet {
            guard providerKind != oldValue else { return }
            provider = providerKind.makeProvider()
            knownIDs = []
            hasLoadedOnce = false
            refresh()
        }
    }

    var isAutoRefreshEnabled: Bool {
        didSet {
            guard isAutoRefreshEnabled != oldValue else { return }
            if isAutoRefreshEnabled { startAutoRefresh() } else { stopAutoRefresh() }
        }
    }

    /// When enabled, a system notification is posted for each newly opened port.
    var notifyOnNewPorts: Bool = false {
        didSet {
            guard notifyOnNewPorts, notifyOnNewPorts != oldValue else { return }
            PortNotifier.shared.requestAccess { [weak self] granted in
                if !granted { self?.notifyOnNewPorts = false }
            }
        }
    }

    private var provider: PortProviding
    private var knownIDs: Set<String> = []
    private var hasLoadedOnce = false
    private var autoRefreshTask: Task<Void, Never>?

    init(providerKind: PortProviderKind = .automatic, autoRefresh: Bool = true) {
        self.providerKind = providerKind
        self.isAutoRefreshEnabled = autoRefresh
        self.provider = providerKind.makeProvider()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    // MARK: - Derived state

    var filteredPorts: [PortInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ports }
        return ports.filter { info in
            info.processName.lowercased().contains(query)
                || String(info.port).contains(query)
                || String(info.pid).contains(query)
                || info.host.lowercased().contains(query)
                || info.transport.rawValue.lowercased().contains(query)
        }
    }

    var listenCount: Int { ports.filter(\.isListening).count }

    // MARK: - Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let provider = self.provider

        Task { [weak self] in
            do {
                let items = try await Task.detached(priority: .utility) {
                    try provider.currentPorts()
                }.value
                self?.apply(items)
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.isRefreshing = false
            }
        }
    }

    private func apply(_ items: [PortInfo]) {
        let ids = Set(items.map(\.id))
        if hasLoadedOnce {
            newlyDiscovered = ids.subtracting(knownIDs)
            if notifyOnNewPorts, !newlyDiscovered.isEmpty {
                PortNotifier.shared.notify(added: items.filter { newlyDiscovered.contains($0.id) })
            }
        } else {
            newlyDiscovered = []
            hasLoadedOnce = true
        }
        knownIDs = ids
        ports = items
        errorMessage = nil
        lastUpdated = Date()
        isRefreshing = false
    }

    func startAutoRefresh(interval: TimeInterval = 3) {
        autoRefreshTask?.cancel()
        refresh()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Actions

    /// Sends `SIGTERM` to the process that owns a port.
    func terminate(pid: Int) throws {
        guard pid > 0 else { return }
        if kill(Int32(pid), SIGTERM) != 0 {
            throw PortTerminationError(pid: pid, code: errno)
        }
        refresh()
    }

    func reportActionError(_ error: Error) {
        actionError = error.localizedDescription
    }

    func clearActionError() {
        actionError = nil
    }
}
