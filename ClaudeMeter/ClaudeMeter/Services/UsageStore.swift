import Foundation
import Observation

/// Single source of truth for usage state. Views observe directly via
/// the Observation macros; UsagePoller is the sole writer.
///
/// Snapshot and error are kept independently: a network failure does not
/// erase the last good snapshot — the popover can show stale data plus a
/// "haven't refreshed since X" hint.
///
/// The store also owns the rolling sample buffers used by `Projector`.
/// Buffers are in-memory only and warm up from empty on launch (see
/// `docs/metrics.md`).
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastRefresh: Date?
    private(set) var lastError: AppError?
    private(set) var fiveHourSamples: [UsageSample] = []
    private(set) var sevenDaySamples: [UsageSample] = []

    /// EWMA half-life for the 5-hour window — short, so today's pattern
    /// surfaces quickly. See `docs/metrics.md`.
    static let fiveHourHalfLife: TimeInterval = 1 * 3600
    /// EWMA half-life for the 7-day window — longer, so single tasks
    /// don't dominate.
    static let sevenDayHalfLife: TimeInterval = 6 * 3600
    /// Window durations.
    static let fiveHourDuration: TimeInterval = 5 * 3600
    static let sevenDayDuration: TimeInterval = 7 * 86400

    private let bufferDuration: TimeInterval = 24 * 3600
    private let bufferCap: Int = 1500

    func updateSnapshot(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        if let fh = snapshot.fiveHour {
            appendSample(to: &fiveHourSamples, utilization: fh.utilization, at: date)
        }
        if let sd = snapshot.sevenDay {
            appendSample(to: &sevenDaySamples, utilization: sd.utilization, at: date)
        }
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
        self.fiveHourSamples.removeAll()
        self.sevenDaySamples.removeAll()
    }

    /// Compute the projection for one window from the live snapshot + buffer.
    /// Returns `nil` whenever `Projector` suppresses (low utilization,
    /// warmup, idle burn, projection lands in the on-pace band).
    func projection(for window: TrackedWindow, now: Date = Date()) -> Projection? {
        switch window {
        case .fiveHour:
            guard let fh = snapshot?.fiveHour else { return nil }
            return Projector.project(
                window: fh,
                samples: fiveHourSamples,
                windowDuration: Self.fiveHourDuration,
                halfLife: Self.fiveHourHalfLife,
                now: now
            )
        case .sevenDay:
            guard let sd = snapshot?.sevenDay else { return nil }
            return Projector.project(
                window: sd,
                samples: sevenDaySamples,
                windowDuration: Self.sevenDayDuration,
                halfLife: Self.sevenDayHalfLife,
                now: now
            )
        }
    }

    /// Append a sample, flushing prior samples if the new utilization is
    /// lower than the most recent (window reset boundary). Then trim the
    /// buffer by age (24h) and absolute count (1500 entries).
    private func appendSample(to buffer: inout [UsageSample], utilization: Double, at date: Date) {
        if let last = buffer.last, utilization < last.utilization {
            buffer.removeAll()
        }
        buffer.append(UsageSample(timestamp: date, utilization: utilization))
        let cutoff = date.addingTimeInterval(-bufferDuration)
        buffer.removeAll(where: { $0.timestamp < cutoff })
        if buffer.count > bufferCap {
            buffer.removeFirst(buffer.count - bufferCap)
        }
    }
}
