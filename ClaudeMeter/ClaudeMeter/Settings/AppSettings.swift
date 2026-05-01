import Foundation
import Observation

/// Persists user preferences to `UserDefaults`. The only place in the app
/// allowed to read/write `UserDefaults` directly — every other module receives
/// settings via this observable surface (see `docs/architecture.md`).
///
/// Currently scaffolding: the values are persisted but no view reads them
/// yet. Wired in when the menu bar custom rendering and settings panel land.
@MainActor
@Observable
final class AppSettings {
    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    var trackedWindow: TrackedWindow {
        didSet { defaults.set(trackedWindow.rawValue, forKey: Keys.trackedWindow) }
    }

    var showUnderPaceAnnotation: Bool {
        didSet { defaults.set(showUnderPaceAnnotation, forKey: Keys.showUnderPaceAnnotation) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let modeRaw = defaults.string(forKey: Keys.displayMode) ?? DisplayMode.vessel.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .vessel

        let windowRaw = defaults.string(forKey: Keys.trackedWindow) ?? TrackedWindow.fiveHour.rawValue
        self.trackedWindow = TrackedWindow(rawValue: windowRaw) ?? .fiveHour

        if defaults.object(forKey: Keys.showUnderPaceAnnotation) != nil {
            self.showUnderPaceAnnotation = defaults.bool(forKey: Keys.showUnderPaceAnnotation)
        } else {
            self.showUnderPaceAnnotation = true
        }
    }

    private enum Keys {
        static let displayMode = "displayMode"
        static let trackedWindow = "trackedWindow"
        static let showUnderPaceAnnotation = "showUnderPaceAnnotation"
    }
}
