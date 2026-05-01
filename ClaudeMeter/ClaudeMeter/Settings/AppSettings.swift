import Foundation
import Observation

/// Persists user preferences to `UserDefaults`. The only place in the app
/// allowed to read/write `UserDefaults` directly — every other module receives
/// settings via this observable surface (see `docs/architecture.md`).
@MainActor
@Observable
final class AppSettings {
    /// Whether the menu bar shows the vessel (utilization) gauge. At least
    /// one of `showUsageInMenuBar` / `showPacingInMenuBar` must be true —
    /// the popover toggles enforce this.
    var showUsageInMenuBar: Bool {
        didSet { defaults.set(showUsageInMenuBar, forKey: Keys.showUsageInMenuBar) }
    }

    /// Whether the menu bar shows the pacing arc + adjacent text.
    var showPacingInMenuBar: Bool {
        didSet { defaults.set(showPacingInMenuBar, forKey: Keys.showPacingInMenuBar) }
    }

    /// Whether to show a percent label to the right of each visible gauge
    /// in the menu bar (utilization next to the vessel, pace ratio next to
    /// the pacing arc).
    var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: Keys.showPercentInMenuBar) }
    }

    var trackedWindow: TrackedWindow {
        didSet { defaults.set(trackedWindow.rawValue, forKey: Keys.trackedWindow) }
    }

    /// Hidden developer overrides — see `DebugSettings`. Only the settings
    /// panel (gated by ⌥⌘⇧D) reads/writes this; runtime views just check
    /// `debug.enabled` and substitute synthesized values when true.
    let debug: DebugSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let usageStored = defaults.object(forKey: Keys.showUsageInMenuBar) != nil
            ? defaults.bool(forKey: Keys.showUsageInMenuBar)
            : true
        let pacingStored = defaults.object(forKey: Keys.showPacingInMenuBar) != nil
            ? defaults.bool(forKey: Keys.showPacingInMenuBar)
            : false
        // Defensive: never let the user end up with no menu-bar content.
        if !usageStored && !pacingStored {
            self.showUsageInMenuBar = true
            self.showPacingInMenuBar = false
        } else {
            self.showUsageInMenuBar = usageStored
            self.showPacingInMenuBar = pacingStored
        }

        if defaults.object(forKey: Keys.showPercentInMenuBar) != nil {
            self.showPercentInMenuBar = defaults.bool(forKey: Keys.showPercentInMenuBar)
        } else {
            self.showPercentInMenuBar = true
        }

        let windowRaw = defaults.string(forKey: Keys.trackedWindow) ?? TrackedWindow.fiveHour.rawValue
        self.trackedWindow = TrackedWindow(rawValue: windowRaw) ?? .fiveHour

        self.debug = DebugSettings(defaults: defaults)
    }

    private enum Keys {
        static let showUsageInMenuBar = "showUsageInMenuBar"
        static let showPacingInMenuBar = "showPacingInMenuBar"
        static let showPercentInMenuBar = "showPercentInMenuBar"
        static let trackedWindow = "trackedWindow"
    }
}
