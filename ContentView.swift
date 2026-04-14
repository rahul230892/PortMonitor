import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = NetworkMonitor()
    @State private var searchText = ""
    @State private var showingError = false
    
    var filteredConnections: [PortConnection] {
        if searchText.isEmpty {
            return monitor.connections
        } else {
            let lowercasedSearch = searchText.lowercased()
            return monitor.connections.filter {
                $0.command.lowercased().contains(lowercasedSearch) ||
                $0.address.lowercased().contains(lowercasedSearch) ||
                "\($0.pid)".contains(lowercasedSearch)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Table(filteredConnections) {
                TableColumn("Command") { connection in
                    Text(connection.command).bold()
                }
                TableColumn("PID") { connection in
                    Text("\(connection.pid)")
                        .foregroundColor(.secondary)
                }
                TableColumn("Protocol") { connection in
                    Text(connection.protocol)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(connection.protocol == "TCP" ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                        .cornerRadius(4)
                }
                TableColumn("User", value: \.user)
                TableColumn("Address") { connection in
                    Text(connection.address)
                        .font(.system(.body, design: .monospaced))
                }
                TableColumn("Action") { connection in
                    Button(action: {
                        monitor.killProcess(pid: connection.pid)
                    }) {
                        Text("Kill")
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .searchable(text: $searchText, prompt: "Search Command, PID, or Address")
            
            if let error = monitor.error {
                Text(error)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
            }
            
            HStack {
                Text("Total ports: \(monitor.connections.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    monitor.fetchConnections()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh Now")
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: monitor.error) { _, newError in   
            if newError != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    monitor.error = nil
                }
            }
        }
    }
}
