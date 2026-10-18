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

/// Drives the port list UI: fetching, filtering, auto-refresh, change detection,
/// per-process traffic rates, export and terminating the owner of a port.
///
/// All the interesting decision logic lives in `PortMonitorCore`
/// (`PortFilter`, `PortListDiffer`, `ProcessGrouping`, `TrafficRateCalculator`,
/// `PortExport`); this type is the thin, UI-facing shell around it.
@MainActor
final class PortListViewModel: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []
    @Published var searchText: String = ""
    @Published var preset: PortFilterPreset = .all
    @Published var groupByProcess: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionError: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    /// Sockets that appeared since the previous refresh, for highlighting.
    @Published private(set) var newlyDiscovered: Set<String> = []

    /// Per-process throughput, keyed by PID.
    @Published private(set) var traffic: [Int: TrafficRate] = [:]

    /// When off, no `nettop` sampling happens and the rate column shows `—`.
    var showsTrafficRates: Bool = true {
        didSet {
            guard showsTrafficRates != oldValue else { return }
            if showsTrafficRates {
                refreshTraffic()
            } else {
                traffic = [:]
                lastTrafficSample = nil
            }
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

    var providerKind: PortProviderKind {
        didSet {
            guard providerKind != oldValue else { return }
            provider = providerKind.makeProvider()
            differ.reset()
            lastTrafficSample = nil
            traffic = [:]
            refresh()
        }
    }

    var isAutoRefreshEnabled: Bool {
        didSet {
            guard isAutoRefreshEnabled != oldValue else { return }
            if isAutoRefreshEnabled { startAutoRefresh() } else { stopAutoRefresh() }
        }
    }

    private var provider: PortProviding
    private var differ = PortListDiffer()
    private var trafficSampler: TrafficSampling
    private var lastTrafficSample: (date: Date, traffic: [ProcessTraffic])?
    private var isSamplingTraffic = false
    private var autoRefreshTask: Task<Void, Never>?

    init(
        providerKind: PortProviderKind = .automatic,
        autoRefresh: Bool = true,
        traffic: TrafficSampling = NettopTrafficProvider()
    ) {
        self.providerKind = providerKind
        self.isAutoRefreshEnabled = autoRefresh
        self.provider = providerKind.makeProvider()
        self.trafficSampler = traffic
        if autoRefresh {
            startAutoRefresh()
        }
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    // MARK: - Derived state

    /// The ports currently shown, after the search text and preset are applied.
    var filteredPorts: [PortInfo] {
        PortFilter.apply(ports, query: searchText, preset: preset)
    }

    /// The filtered ports folded into one row per process.
    var processGroups: [ProcessGroup] {
        ProcessGrouping.groups(from: filteredPorts)
    }

    var listenCount: Int { ports.filter(\.isListening).count }

    func rate(for pid: Int) -> TrafficRate? { traffic[pid] }

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
        let update = differ.apply(items)

        newlyDiscovered = update.addedIDs
        if notifyOnNewPorts, !update.isInitialLoad, !update.added.isEmpty {
            PortNotifier.shared.notify(added: update.added)
        }

        ports = items
        errorMessage = nil
        lastUpdated = Date()
        isRefreshing = false

        refreshTraffic()
    }

    // MARK: - Traffic

    /// Samples per-process counters and turns the delta into rates.
    private func refreshTraffic() {
        guard showsTrafficRates, !isSamplingTraffic else { return }
        isSamplingTraffic = true
        let sampler = trafficSampler
        let sampledAt = Date()

        Task { [weak self] in
            let current = (try? await Task.detached(priority: .utility) {
                try sampler.sample()
            }.value) ?? []

            guard let self else { return }
            self.isSamplingTraffic = false
            self.applyTraffic(current, at: sampledAt)
        }
    }

    private func applyTraffic(_ current: [ProcessTraffic], at date: Date) {
        defer { lastTrafficSample = (date, current) }

        guard let previous = lastTrafficSample else { return }
        traffic = TrafficRateCalculator.rates(
            previous: previous.traffic,
            current: current,
            interval: date.timeIntervalSince(previous.date)
        )
    }

    // MARK: - Export

    /// Serialises the rows currently on screen.
    func exportData(format: PortExport.Format) throws -> Data {
        try PortExport.data(filteredPorts, format: format)
    }

    // MARK: - Auto refresh

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
