import SwiftUI
import UniformTypeIdentifiers
import PortMonitorCore

@MainActor
struct ContentView: View {
    @ObservedObject var viewModel: PortListViewModel

    @State private var selection: PortInfo.ID?
    @State private var pendingTermination: PortInfo?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 460)
        .confirmationDialog(
            "Terminate process?",
            isPresented: terminationRequested,
            presenting: pendingTermination
        ) { port in
            Button("Terminate \(port.processName) (PID \(port.pid))", role: .destructive) {
                terminate(port)
            }
            Button("Cancel", role: .cancel) {
                pendingTermination = nil
            }
        } message: { port in
            Text("Sends SIGTERM to \(port.processName) (PID \(port.pid)). Save your work first.")
        }
        .alert(
            "Action failed",
            isPresented: actionErrorPresented
        ) {
            Button("OK") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("Filter by port, process, PID or address", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Filter", selection: $viewModel.preset) {
                    ForEach(PortFilterPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .help("Narrow the list with a preset")

                Picker("Source", selection: $viewModel.providerKind) {
                    ForEach(PortProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .help("Where open ports are read from")
            }

            HStack(spacing: 12) {
                Toggle("Group by process", isOn: $viewModel.groupByProcess)
                    .toggleStyle(.checkbox)
                    .help("Show one expandable row per process")

                Toggle("Traffic rates", isOn: $viewModel.showsTrafficRates)
                    .toggleStyle(.checkbox)
                    .help("Sample per-process network throughput with nettop")

                Toggle("Auto-refresh", isOn: $viewModel.isAutoRefreshEnabled)
                    .toggleStyle(.switch)

                Spacer()

                exportMenu

                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .padding(12)
    }

    private var exportMenu: some View {
        Menu {
            ForEach(PortExport.Format.allCases) { format in
                Button("Export as \(format.displayName)…") { export(format) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .fixedSize()
        .help("Save the rows currently shown")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            placeholder(systemImage: "exclamationmark.triangle", message: error)
        } else if viewModel.filteredPorts.isEmpty {
            placeholder(systemImage: "network.slash", message: "No open ports found")
        } else if viewModel.groupByProcess {
            groupedList
        } else {
            table
        }
    }

    private var table: some View {
        Table(viewModel.filteredPorts, selection: $selection) {
            TableColumn("Port") { info in
                HStack(spacing: 6) {
                    if viewModel.newlyDiscovered.contains(info.id) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .help("New since last refresh")
                    }
                    Text("\(info.port)").monospacedDigit()
                }
            }
            .width(min: 60, ideal: 70)

            TableColumn("Proto") { info in
                Text(info.transport.rawValue)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Process") { info in
                Text(info.processName)
            }

            TableColumn("PID") { info in
                Text("\(info.pid)").monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Address") { info in
                Text(info.host)
            }

            TableColumn("State") { info in
                Text(info.state ?? "—")
            }
            .width(min: 70, ideal: 90)

            TableColumn("Rate") { info in
                if viewModel.showsTrafficRates {
                    Text(RateFormat.compact(viewModel.rate(for: info.pid)))
                        .monospacedDigit()
                        .foregroundStyle(viewModel.rate(for: info.pid) == nil ? .secondary : .primary)
                        .help("Per-process throughput for \(info.processName)")
                }
            }
            .width(min: 130, ideal: 170)
        }
        .contextMenu(forSelectionType: PortInfo.ID.self) { ids in
            if let port = port(for: ids.first) {
                Button("Terminate \(port.processName)…", role: .destructive) {
                    pendingTermination = port
                }
            }
        }
    }

    private var groupedList: some View {
        List {
            ForEach(viewModel.processGroups) { group in
                DisclosureGroup {
                    ForEach(group.ports) { info in
                        socketRow(info, pid: group.pid)
                    }
                } label: {
                    groupRow(group)
                }
                .contextMenu {
                    Button("Terminate \(group.processName)…", role: .destructive) {
                        pendingTermination = group.ports.first
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func groupRow(_ group: ProcessGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.processName)
                .fontWeight(.semibold)
            Text("PID \(group.pid)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Text("\(group.portCount) port\(group.portCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)

            if viewModel.showsTrafficRates {
                Text(RateFormat.compact(viewModel.rate(for: group.pid)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func socketRow(_ info: PortInfo, pid: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(info.port)/\(info.transport.rawValue)")
                .monospacedDigit()
            Text(info.host)
                .foregroundStyle(.secondary)
            Spacer()
            Text(info.state ?? "—")
                .foregroundStyle(.secondary)
            if viewModel.newlyDiscovered.contains(info.id) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .help("New since last refresh")
            }
        }
        .padding(.leading, 4)
    }

    private func placeholder(systemImage: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
            Text(message)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            let count = viewModel.filteredPorts.count
            Text("\(count) port\(count == 1 ? "" : "s")")
            Text("•")
            Text("\(viewModel.listenCount) listening")
                .foregroundStyle(.secondary)
            if viewModel.groupByProcess {
                Text("•")
                Text("\(viewModel.processGroups.count) processes")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let selected = port(for: selection) {
                Button("Terminate \(selected.processName)…", role: .destructive) {
                    pendingTermination = selected
                }
            }

            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
    }

    // MARK: - Helpers

    private func port(for id: PortInfo.ID?) -> PortInfo? {
        guard let id else { return nil }
        return viewModel.ports.first { $0.id == id }
    }

    private var terminationRequested: Binding<Bool> {
        Binding(
            get: { pendingTermination != nil },
            set: { if !$0 { pendingTermination = nil } }
        )
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.clearActionError() } }
        )
    }

    private func terminate(_ port: PortInfo) {
        do {
            try viewModel.terminate(pid: port.pid)
        } catch {
            viewModel.reportActionError(error)
        }
        pendingTermination = nil
    }

    private func export(_ format: PortExport.Format) {
        let panel = NSSavePanel()
        panel.title = "Export ports"
        panel.nameFieldStringValue = "ports.\(format.fileExtension)"
        switch format {
        case .csv: panel.allowedContentTypes = [.commaSeparatedText]
        case .json: panel.allowedContentTypes = [.json]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.exportData(format: format).write(to: url)
        } catch {
            viewModel.reportActionError(error)
        }
    }
}
