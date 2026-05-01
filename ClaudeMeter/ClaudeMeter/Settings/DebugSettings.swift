import Foundation
import Observation

/// Hidden developer-only override for the values displayed by the menu-bar
/// label and popover. When `enabled` is true, the views read synthesized
/// values from this struct instead of the real `UsageStore` data, letting a
/// developer step through every visual state (low/high utilization, on-pace,
/// over-pace, under-pace) without having to actually burn the account.
///
/// All fields persist to `UserDefaults` so the override survives relaunches.
/// Hidden in `SettingsView` behind a ⌥⌘⇧D shortcut.
@MainActor
@Observable
final class DebugSettings {
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }

    var fiveHourUtil: Double {
        didSet { defaults.set(fiveHourUtil, forKey: Keys.fiveHourUtil) }
    }
    var fiveHourMinutesToReset: Double {
        didSet { defaults.set(fiveHourMinutesToReset, forKey: Keys.fiveHourMinutesToReset) }
    }
    var fiveHourOutcome: DebugOutcomeKind {
        didSet { defaults.set(fiveHourOutcome.rawValue, forKey: Keys.fiveHourOutcome) }
    }
    var fiveHourOverPaceHours: Double {
        didSet { defaults.set(fiveHourOverPaceHours, forKey: Keys.fiveHourOverPaceHours) }
    }
    var fiveHourUnusedFraction: Double {
        didSet { defaults.set(fiveHourUnusedFraction, forKey: Keys.fiveHourUnusedFraction) }
    }

    var sevenDayUtil: Double {
        didSet { defaults.set(sevenDayUtil, forKey: Keys.sevenDayUtil) }
    }
    var sevenDayMinutesToReset: Double {
        didSet { defaults.set(sevenDayMinutesToReset, forKey: Keys.sevenDayMinutesToReset) }
    }
    var sevenDayOutcome: DebugOutcomeKind {
        didSet { defaults.set(sevenDayOutcome.rawValue, forKey: Keys.sevenDayOutcome) }
    }
    var sevenDayOverPaceHours: Double {
        didSet { defaults.set(sevenDayOverPaceHours, forKey: Keys.sevenDayOverPaceHours) }
    }
    var sevenDayUnusedFraction: Double {
        didSet { defaults.set(sevenDayUnusedFraction, forKey: Keys.sevenDayUnusedFraction) }
    }

    /// Simulate the API being unreachable while the cached snapshot stays
    /// visible — exercises the rate-limited / network-down popover state.
    var apiUnavailable: Bool {
        didSet { defaults.set(apiUnavailable, forKey: Keys.apiUnavailable) }
    }

    /// Minutes since the last successful poll, fed into the popover's
    /// "Updated X ago" footer so you can preview stale-data styling.
    var minutesSinceUpdate: Double {
        didSet { defaults.set(minutesSinceUpdate, forKey: Keys.minutesSinceUpdate) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.enabled = defaults.bool(forKey: Keys.enabled)
        self.fiveHourUtil = Self.read(defaults, key: Keys.fiveHourUtil, fallback: 50)
        self.fiveHourMinutesToReset = Self.read(defaults, key: Keys.fiveHourMinutesToReset, fallback: 120)
        self.fiveHourOutcome = DebugOutcomeKind(rawValue: defaults.string(forKey: Keys.fiveHourOutcome) ?? "") ?? .none
        self.fiveHourOverPaceHours = Self.read(defaults, key: Keys.fiveHourOverPaceHours, fallback: 6)
        self.fiveHourUnusedFraction = Self.read(defaults, key: Keys.fiveHourUnusedFraction, fallback: 0.3)
        self.sevenDayUtil = Self.read(defaults, key: Keys.sevenDayUtil, fallback: 50)
        self.sevenDayMinutesToReset = Self.read(defaults, key: Keys.sevenDayMinutesToReset, fallback: 24 * 60)
        self.sevenDayOutcome = DebugOutcomeKind(rawValue: defaults.string(forKey: Keys.sevenDayOutcome) ?? "") ?? .none
        self.sevenDayOverPaceHours = Self.read(defaults, key: Keys.sevenDayOverPaceHours, fallback: 24)
        self.sevenDayUnusedFraction = Self.read(defaults, key: Keys.sevenDayUnusedFraction, fallback: 0.3)
        self.apiUnavailable = defaults.bool(forKey: Keys.apiUnavailable)
        self.minutesSinceUpdate = Self.read(defaults, key: Keys.minutesSinceUpdate, fallback: 0)
    }

    private static func read(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    // MARK: - Synthesis

    func syntheticSnapshot(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageWindow(
                utilization: fiveHourUtil,
                resetsAt: now.addingTimeInterval(fiveHourMinutesToReset * 60)
            ),
            sevenDay: UsageWindow(
                utilization: sevenDayUtil,
                resetsAt: now.addingTimeInterval(sevenDayMinutesToReset * 60)
            )
        )
    }

    func syntheticProjection(for window: TrackedWindow) -> Projection? {
        switch window {
        case .fiveHour:
            return projection(
                outcome: fiveHourOutcome,
                overPaceHours: fiveHourOverPaceHours,
                unusedFraction: fiveHourUnusedFraction,
                minutesToReset: fiveHourMinutesToReset
            )
        case .sevenDay:
            return projection(
                outcome: sevenDayOutcome,
                overPaceHours: sevenDayOverPaceHours,
                unusedFraction: sevenDayUnusedFraction,
                minutesToReset: sevenDayMinutesToReset
            )
        }
    }

    private func projection(
        outcome: DebugOutcomeKind,
        overPaceHours: Double,
        unusedFraction: Double,
        minutesToReset: Double
    ) -> Projection? {
        switch outcome {
        case .none:
            return nil
        case .onPace:
            return Projection(paceRatio: 1.0, confidence: .full, outcome: .onPace)
        case .overPace:
            return Projection(
                paceRatio: 1.5,
                confidence: .full,
                outcome: .overPace(deadTime: max(0, overPaceHours) * 3600)
            )
        case .underPace:
            let frac = max(0, min(1, unusedFraction))
            return Projection(
                paceRatio: 0.6,
                confidence: .full,
                outcome: .underPace(
                    unusedFraction: frac,
                    unusedTime: frac * minutesToReset * 60
                )
            )
        }
    }

    private enum Keys {
        static let enabled = "debug.enabled"
        static let fiveHourUtil = "debug.fiveHour.util"
        static let fiveHourMinutesToReset = "debug.fiveHour.minutesToReset"
        static let fiveHourOutcome = "debug.fiveHour.outcome"
        static let fiveHourOverPaceHours = "debug.fiveHour.overPaceHours"
        static let fiveHourUnusedFraction = "debug.fiveHour.unusedFraction"
        static let sevenDayUtil = "debug.sevenDay.util"
        static let sevenDayMinutesToReset = "debug.sevenDay.minutesToReset"
        static let sevenDayOutcome = "debug.sevenDay.outcome"
        static let sevenDayOverPaceHours = "debug.sevenDay.overPaceHours"
        static let sevenDayUnusedFraction = "debug.sevenDay.unusedFraction"
        static let apiUnavailable = "debug.apiUnavailable"
        static let minutesSinceUpdate = "debug.minutesSinceUpdate"
    }
}

enum DebugOutcomeKind: String, CaseIterable, Codable, Sendable {
    case none, onPace, overPace, underPace

    var label: String {
        switch self {
        case .none: return "No projection"
        case .onPace: return "On pace"
        case .overPace: return "Over pace"
        case .underPace: return "Under pace"
        }
    }
}
