import Foundation
import Combine

struct PortConnection: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let pid: Int
    let user: String
    let `protocol`: String
    let address: String
}

class NetworkMonitor: ObservableObject {
    @Published var connections: [PortConnection] = []
    @Published var error: String? = nil
    
    private var cancellable: AnyCancellable?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        fetchConnections()
        cancellable = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchConnections()
            }
    }
    
    func stopMonitoring() {
        cancellable?.cancel()
    }
    
    func fetchConnections() {
        DispatchQueue.global(qos: .userInitiated).async {
            let tcpConnections = self.runLsof(arguments: ["-i4TCP", "-i6TCP", "-sTCP:LISTEN", "-n", "-P"], proto: "TCP")
            let udpConnections = self.runLsof(arguments: ["-i4UDP", "-i6UDP", "-n", "-P"], proto: "UDP")
            
            let allConnections = tcpConnections + udpConnections
            
            // Filter duplicates by PID and Address (since IPv4 and IPv6 might duplicate or multiple FDs might show)
            var uniqueSet = Set<String>()
            var uniqueConnections = [PortConnection]()
            
            for conn in allConnections {
                let key = "\(conn.pid)-\(conn.protocol)-\(conn.address)"
                if !uniqueSet.contains(key) {
                    uniqueSet.insert(key)
                    uniqueConnections.append(conn)
                }
            }
            
            // Sort by Command, then PID
            uniqueConnections.sort {
                if $0.command == $1.command {
                    return $0.pid < $1.pid
                }
                return $0.command < $1.command
            }
            
            DispatchQueue.main.async {
                self.connections = uniqueConnections
            }
        }
    }
    
    private func runLsof(arguments: [String], proto: String) -> [PortConnection] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return parseLsofOutput(output, proto: proto)
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Error running lsof: \(error.localizedDescription)"
            }
        }
        return []
    }
    
    private func parseLsofOutput(_ output: String, proto: String) -> [PortConnection] {
        var results: [PortConnection] = []
        let lines = output.components(separatedBy: .newlines)
        
        // Skip header
        for line in lines {
            if line.isEmpty || line.hasPrefix("COMMAND") { continue }
            
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 9 {
                let command = String(parts[0])
                guard let pid = Int(parts[1]) else { continue }
                let user = String(parts[2])
                
                var nameParts = [String]()
                for i in 8..<parts.count {
                    nameParts.append(String(parts[i]))
                }
                let address = nameParts.joined(separator: " ")
                let cleanAddress = address.replacingOccurrences(of: "(LISTEN)", with: "").trimmingCharacters(in: .whitespaces)
                
                results.append(PortConnection(command: command, pid: pid, user: user, protocol: proto, address: cleanAddress))
            }
        }
        return results
    }
    
    func killProcess(pid: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = ["-9", "\(pid)"]
            
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                        DispatchQueue.main.async {
                            self.error = "Failed to kill process \(pid): \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error = nil
                    }
                    // Refresh immediately
                    self.fetchConnections()
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Error killing process \(pid): \(error.localizedDescription)"
                }
            }
        }
    }
}
