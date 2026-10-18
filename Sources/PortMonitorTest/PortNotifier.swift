import Foundation
import UserNotifications
import PortMonitorCore

/// Best-effort system notifications for newly opened ports.
///
/// `UNUserNotificationCenter` requires a real application bundle, so every
/// entry point here becomes a no-op when the app runs unbundled (for example
/// via `swift run`). This keeps notifications from ever destabilising the
/// primary code path.
final class PortNotifier {
    static let shared = PortNotifier()

    private init() {}

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    // Created lazily so `UNUserNotificationCenter.current()` is only ever
    // touched when the process actually has a bundle.
    private lazy var center: UNUserNotificationCenter? = {
        isBundled ? UNUserNotificationCenter.current() : nil
    }()

    /// Requests permission, calling back with the outcome. Reports `false`
    /// when notifications are unavailable.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        guard let center else {
            completion(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Posts a notification per newly discovered port (capped to avoid spam).
    func notify(added: [PortInfo]) {
        guard let center, !added.isEmpty else { return }
        for info in added.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = "New port \(info.port)/\(info.transport.rawValue)"
            content.body = "\(info.processName) (PID \(info.pid)) is now listening"
            content.sound = .default
            center.add(
                UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
            )
        }
    }
}
