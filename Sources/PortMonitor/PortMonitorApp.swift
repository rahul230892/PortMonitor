import SwiftUI
import AppKit
import PortMonitorCore

@main
struct PortMonitorApp: App {
    @StateObject private var viewModel = PortListViewModel()
    @StateObject private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup("Port Monitor", id: "main") {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 560)

        MenuBarExtra {
            MenuBarContent(viewModel: viewModel, preferences: preferences)
        } label: {
            Label("\(viewModel.listenCount)", systemImage: "network")
        }
    }
}

/// Popover contents for the menu-bar item.
private struct MenuBarContent: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var preferences: AppPreferences
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

        Toggle("Traffic rates", isOn: $viewModel.showsTrafficRates)

        Divider()

        Toggle("Menu bar only", isOn: $preferences.menuBarOnly)
            .help("Hide the Dock icon and live only in the menu bar")

        Divider()

        Button("Quit Port Monitor") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
