import Foundation

/// Pure functions that turn a `UsageWindow` into a `Projection`.
/// No state, no side effects — all inputs are arguments, `now` is
/// injectable for tests.
///
/// The projection is a single-snapshot linear extrapolation: assume the
/// burn rate so far (`current_util / elapsed`) continues unchanged until
/// reset. This trades responsiveness for simplicity — bursty usage will
/// over-project early and under-project after the burst — but it doesn't
/// require a sample history, so it produces a value from poll #1.
enum Projector {

    /// "On pace" band on projected end-of-window utilization, in
    /// percentage points around 100. Within ±this, the outcome is .onPace
    /// (no annotation). Drives popover annotation visibility.
    static let onPaceBand: Double = 5

    /// Returns the projection for a window, or `nil` when the inputs
    /// can't produce a meaningful pace ratio (no reset time, zero
    /// utilization, the window has just started, or the window is past
    /// its reset).
    static func project(
        window: UsageWindow,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> Projection? {
        let util = window.utilization
        guard util > 0 else { return nil }
        guard let resetsAt = window.resetsAt else { return nil }

        let secondsUntilReset = resetsAt.timeIntervalSince(now)
        guard secondsUntilReset > 0 else { return nil }

        let elapsed = windowDuration - secondsUntilReset
        guard elapsed > 0 else { return nil }
        let expectedUtil = (elapsed / windowDuration) * 100
        guard expectedUtil > 0 else { return nil }
        let paceRatio = util / expectedUtil

        // Linear extrapolation: average burn rate so far carries forward.
        let burnRatePerSec = util / elapsed
        let projectedAtReset = util + burnRatePerSec * secondsUntilReset

        let outcome: Projection.Outcome
        if abs(projectedAtReset - 100) < onPaceBand {
            outcome = .onPace
        } else if projectedAtReset >= 100 {
            let secondsUntilFull = (100 - util) / burnRatePerSec
            let deadTime = max(0, secondsUntilReset - secondsUntilFull)
            outcome = .overPace(deadTime: deadTime)
        } else {
            let unusedAtReset = max(0, 100 - projectedAtReset)
            let unusedFraction = unusedAtReset / 100
            let unusedTime = unusedAtReset / burnRatePerSec
            outcome = .underPace(unusedFraction: unusedFraction, unusedTime: unusedTime)
        }

        return Projection(paceRatio: paceRatio, confidence: .full, outcome: outcome)
    }
}
