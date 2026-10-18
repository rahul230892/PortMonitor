import Foundation
import AppKit

/// Small, persisted user preferences that affect how the app presents itself.
///
/// Currently just the "menu bar only" mode: when enabled the app becomes an
/// accessory (no Dock icon, no app switcher entry) and lives in the menu bar.
@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let menuBarOnly = "menuBarOnly"
    }

    private let defaults: UserDefaults

    @Published var menuBarOnly: Bool {
        didSet {
            guard menuBarOnly != oldValue else { return }
            defaults.set(menuBarOnly, forKey: Key.menuBarOnly)
            applyActivationPolicy()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.menuBarOnly = defaults.bool(forKey: Key.menuBarOnly)
        applyActivationPolicy()
    }

    /// Mirrors ``menuBarOnly`` onto the process activation policy.
    ///
    /// `.accessory` removes the Dock icon while keeping the menu bar item and
    /// the ability to open the main window; `.regular` restores normal behaviour.
    func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}
