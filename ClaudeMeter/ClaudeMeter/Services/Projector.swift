import Foundation

/// Pure functions that turn a `UsageWindow` and a sample buffer into a
/// `Projection`. No state, no side effects — all inputs are arguments,
/// `now` is injectable for tests.
///
/// Implements the rules in `docs/metrics.md`: pace ratio, EWMA burn rate,
/// projected dead time / unused capacity, on-pace band, confidence gating.
enum Projector {

    /// Confidence/utilization gate: hide the projection entirely below this.
    static let minimumUtilization: Double = 10
    /// Below this we still project, but mark as `.low` confidence.
    static let fullConfidenceUtilization: Double = 25
    /// Need at least this many samples to compute a meaningful EWMA.
    static let minimumSampleCount: Int = 5
    /// "On pace" band on projected end-of-window utilization, in
    /// percentage points around 100. Within ±this, the outcome is .onPace
    /// (no annotation). Drives popover annotation visibility.
    static let onPaceBand: Double = 5

    /// Returns the projection for a window, or `nil` when any of the
    /// suppression rules fire (low utilization, insufficient samples, idle
    /// burn, or projection landing inside the suppression band).
    static func project(
        window: UsageWindow,
        samples: [UsageSample],
        windowDuration: TimeInterval,
        halfLife: TimeInterval,
        now: Date = Date()
    ) -> Projection? {
        let util = window.utilization
        guard util >= minimumUtilization else { return nil }
        guard samples.count >= minimumSampleCount else { return nil }
        guard let resetsAt = window.resetsAt else { return nil }

        let secondsUntilReset = resetsAt.timeIntervalSince(now)
        guard secondsUntilReset > 0 else { return nil }

        let elapsed = windowDuration - secondsUntilReset
        guard elapsed > 0 else { return nil }
        let expectedUtil = (elapsed / windowDuration) * 100
        guard expectedUtil > 0 else { return nil }
        let paceRatio = util / expectedUtil

        guard let burnRate = ewmaBurnRate(samples: samples, halfLife: halfLife, now: now),
              burnRate > 0 else { return nil }

        let projectedAtReset = util + burnRate * secondsUntilReset

        // Classify by projected end state, not by pace ratio. Otherwise a
        // burn rate that has just diverged from the pace-implied rate could
        // produce nonsense (e.g. paceRatio > 1.05 but burn rate too low to
        // actually overshoot, giving deadTime ≈ 0).
        let outcome: Projection.Outcome
        if abs(projectedAtReset - 100) < onPaceBand {
            outcome = .onPace
        } else if projectedAtReset >= 100 {
            let secondsUntilFull = (100 - util) / burnRate
            let deadTime = max(0, secondsUntilReset - secondsUntilFull)
            outcome = .overPace(deadTime: deadTime)
        } else {
            let unusedAtReset = max(0, 100 - projectedAtReset)
            let unusedFraction = unusedAtReset / 100
            let unusedTime = unusedAtReset / burnRate
            outcome = .underPace(unusedFraction: unusedFraction, unusedTime: unusedTime)
        }

        let confidence: Projection.Confidence = util < fullConfidenceUtilization ? .low : .full
        return Projection(paceRatio: paceRatio, confidence: confidence, outcome: outcome)
    }

    /// Time-weighted EWMA of the inter-sample burn rate (utilization
    /// percentage points per second). Each pair of consecutive samples
    /// contributes a rate weighted by exp(-λ·age) where λ = ln(2)/halfLife
    /// and age is measured from `now` to the later sample.
    static func ewmaBurnRate(
        samples: [UsageSample],
        halfLife: TimeInterval,
        now: Date = Date()
    ) -> Double? {
        guard samples.count >= 2, halfLife > 0 else { return nil }
        let sorted = samples.sorted(by: { $0.timestamp < $1.timestamp })
        let lambda = log(2.0) / halfLife
        var weightedSum: Double = 0
        var weightTotal: Double = 0
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let rate = (curr.utilization - prev.utilization) / dt
            let age = max(0, now.timeIntervalSince(curr.timestamp))
            let weight = exp(-lambda * age)
            weightedSum += weight * rate
            weightTotal += weight
        }
        return weightTotal > 0 ? weightedSum / weightTotal : nil
    }
}
