import Foundation
import Observation

/// Single source of truth for usage state. Views observe directly via
/// the Observation macros; UsagePoller is the sole writer.
///
/// Snapshot and error are kept independently: a network failure does not
/// erase the last good snapshot — the popover can show stale data plus a
/// "haven't refreshed since X" hint.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastRefresh: Date?
    private(set) var lastError: AppError?

    /// Window durations.
    static let fiveHourDuration: TimeInterval = 5 * 3600
    static let sevenDayDuration: TimeInterval = 7 * 86400

    func updateSnapshot(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        self.snapshot = snapshot
        self.lastRefresh = date
        self.lastError = nil
    }

    func recordError(_ error: AppError) {
        self.lastError = error
    }

    func clear() {
        self.snapshot = nil
        self.lastRefresh = nil
        self.lastError = nil
    }

    /// Compute the projection for one window from the live snapshot.
    /// Returns `nil` whenever `Projector` can't produce a value (no
    /// reset time, zero utilization, etc.).
    func projection(for window: TrackedWindow, now: Date = Date()) -> Projection? {
        switch window {
        case .fiveHour:
            guard let fh = snapshot?.fiveHour else { return nil }
            return Projector.project(
                window: fh,
                windowDuration: Self.fiveHourDuration,
                now: now
            )
        case .sevenDay:
            guard let sd = snapshot?.sevenDay else { return nil }
            return Projector.project(
                window: sd,
                windowDuration: Self.sevenDayDuration,
                now: now
            )
        }
    }
}
