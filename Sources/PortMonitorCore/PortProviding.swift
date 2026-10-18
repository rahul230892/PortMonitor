import Foundation

/// Supplies the set of open ports for the current system.
///
/// Abstracting the data source keeps the UI and view model testable.
public protocol PortProviding: Sendable {
    func currentPorts() throws -> [PortInfo]
}
