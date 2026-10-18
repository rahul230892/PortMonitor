import SwiftUI
import AppKit
import PortMonitorCore

@main
struct PortMonitorApp: App {
    @StateObject private var viewModel = PortListViewModel()

    var body: some Scene {
        WindowGroup("Port Monitor", id: "main") {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 820, height: 520)

        MenuBarExtra {
            MenuBarContent(viewModel: viewModel)
        } label: {
            Label("\(viewModel.listenCount)", systemImage: "network")
        }
    }
}

/// Popover contents for the menu-bar item.
private struct MenuBarContent: View {
    @ObservedObject var viewModel: PortListViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(viewModel.listenCount) listening · \(viewModel.ports.count) total")

        Divider()

        Button("Open Port Monitor") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Button("Refresh Now") {
            viewModel.refresh()
        }

        Toggle("Auto-refresh", isOn: $viewModel.isAutoRefreshEnabled)

        Toggle("Notify on new ports", isOn: $viewModel.notifyOnNewPorts)

        Divider()

        Button("Quit Port Monitor") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
