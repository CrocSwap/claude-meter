import Foundation
import Testing
@testable import ClaudeMeter

@Suite("Projector")
struct ProjectorTests {

    static let now = Date(timeIntervalSince1970: 1_777_577_933)
    static let fiveHourDuration: TimeInterval = 5 * 3600
    static let fiveHourHalfLife: TimeInterval = 1 * 3600

    /// Build a buffer of `count` evenly-spaced samples ending `endingAt`,
    /// where utilization climbs linearly from `start` to `end`.
    static func ramp(
        from start: Double,
        to end: Double,
        count: Int,
        spacing: TimeInterval = 60,
        endingAt endTime: Date = ProjectorTests.now.addingTimeInterval(-30)
    ) -> [UsageSample] {
        (0..<count).map { i in
            let frac = count > 1 ? Double(i) / Double(count - 1) : 0
            let util = start + (end - start) * frac
            let t = endTime.addingTimeInterval(-Double(count - 1 - i) * spacing)
            return UsageSample(timestamp: t, utilization: util)
        }
    }

    @Test("Below 10% utilization → nil")
    func belowMinimumUtilization() {
        let window = UsageWindow(utilization: 5, resetsAt: Self.now.addingTimeInterval(3600))
        let samples = Self.ramp(from: 0, to: 5, count: 10)
        let p = Projector.project(window: window, samples: samples,
                                  windowDuration: Self.fiveHourDuration,
                                  halfLife: Self.fiveHourHalfLife,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Fewer than 5 samples → nil")
    func belowMinimumSamples() {
        let window = UsageWindow(utilization: 40, resetsAt: Self.now.addingTimeInterval(3600))
        let samples = Self.ramp(from: 30, to: 40, count: 4)
        let p = Projector.project(window: window, samples: samples,
                                  windowDuration: Self.fiveHourDuration,
                                  halfLife: Self.fiveHourHalfLife,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Missing resetsAt → nil")
    func missingResetsAt() {
        let window = UsageWindow(utilization: 40, resetsAt: nil)
        let samples = Self.ramp(from: 30, to: 40, count: 10)
        let p = Projector.project(window: window, samples: samples,
                                  windowDuration: Self.fiveHourDuration,
                                  halfLife: Self.fiveHourHalfLife,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Idle / non-positive burn rate → nil")
    func idleBurnRate() {
        let window = UsageWindow(utilization: 40, resetsAt: Self.now.addingTimeInterval(3600))
        let samples = Self.ramp(from: 40, to: 40, count: 10)
        let p = Projector.project(window: window, samples: samples,
                                  windowDuration: Self.fiveHourDuration,
                                  halfLife: Self.fiveHourHalfLife,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Heavy burn over short remaining → over-pace with measurable dead time")
    func overPaceClassification() {
        // 5h window, 2h elapsed, 3h remaining, currently at 80%.
        // Expected at this point ≈ 40%, paceRatio ≈ 2.0.
        // Burn 0→80 in ~10 min → very high rate → projection well above 100.
        let resetsAt = Self.now.addingTimeInterval(3 * 3600)
        let window = UsageWindow(utilization: 80, resetsAt: resetsAt)
        let samples = Self.ramp(from: 0, to: 80, count: 10)
        guard let p = Projector.project(window: window, samples: samples,
                                        windowDuration: Self.fiveHourDuration,
                                        halfLife: Self.fiveHourHalfLife,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        if case .overPace(let deadTime) = p.outcome {
            #expect(deadTime > 0)
        } else {
            Issue.record("expected overPace outcome")
        }
        #expect(p.confidence == Projection.Confidence.full)
        #expect(p.paceRatio > 1.5)
    }

    @Test("Light burn over long remaining → under-pace with unused capacity")
    func underPaceClassification() {
        // 7d window, 5d remaining, currently at 20%.
        // Burn 0→20 over 1.67h (10 samples × 600s spacing). Slow projected slope.
        let sevenDayDuration: TimeInterval = 7 * 86400
        let resetsAt = Self.now.addingTimeInterval(5 * 86400)
        let window = UsageWindow(utilization: 20, resetsAt: resetsAt)
        let samples = Self.ramp(from: 19.97, to: 20, count: 10, spacing: 600)
        guard let p = Projector.project(window: window, samples: samples,
                                        windowDuration: sevenDayDuration,
                                        halfLife: 6 * 3600,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        if case .underPace(let unusedFraction, let unusedTime) = p.outcome {
            #expect(unusedFraction > 0)
            #expect(unusedFraction < 1)
            #expect(unusedTime > 0)
        } else {
            Issue.record("expected underPace outcome")
        }
        #expect(p.paceRatio < 1)
    }

    @Test("On-pace band collapses outcome to .onPace")
    func onPaceClassification() {
        // 5h window, 2.5h elapsed (so 2.5h remaining), currently at 50%.
        // Burn rate ramp from 49.99 → 50 means EWMA ≈ pace-implied rate of
        // 50 / (2.5h) → projected at reset ≈ 100 → in the on-pace band.
        let resetsAt = Self.now.addingTimeInterval(2.5 * 3600)
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt)
        let burnPerSec = 50.0 / (2.5 * 3600)
        let samples = (0..<10).map { i -> UsageSample in
            let t = Self.now.addingTimeInterval(-Double(9 - i) * 60 - 30)
            // Reverse-fill samples consistent with the burn-per-sec rate
            let util = 50.0 - burnPerSec * Double(9 - i) * 60
            return UsageSample(timestamp: t, utilization: util)
        }
        guard let p = Projector.project(window: window, samples: samples,
                                        windowDuration: Self.fiveHourDuration,
                                        halfLife: Self.fiveHourHalfLife,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(p.outcome == Projection.Outcome.onPace)
    }

    @Test("Low confidence band — utilization 10–25% gets .low")
    func lowConfidence() {
        // 5h window, 4h remaining, currently at 18% — under pace.
        let resetsAt = Self.now.addingTimeInterval(4 * 3600)
        let window = UsageWindow(utilization: 18, resetsAt: resetsAt)
        let samples = Self.ramp(from: 17.95, to: 18, count: 10)
        guard let p = Projector.project(window: window, samples: samples,
                                        windowDuration: Self.fiveHourDuration,
                                        halfLife: Self.fiveHourHalfLife,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(p.confidence == Projection.Confidence.low)
    }

    @Test("EWMA returns nil for fewer than two samples")
    func ewmaInsufficientSamples() {
        #expect(Projector.ewmaBurnRate(samples: [], halfLife: 3600, now: Self.now) == nil)
        let one = [UsageSample(timestamp: Self.now, utilization: 10)]
        #expect(Projector.ewmaBurnRate(samples: one, halfLife: 3600, now: Self.now) == nil)
    }

    @Test("EWMA computes a constant rate correctly")
    func ewmaConstantRate() {
        // 11 samples over 600s, util climbing 0→60. Constant rate = 0.1 pp/s.
        let samples = (0..<11).map { i in
            UsageSample(
                timestamp: Self.now.addingTimeInterval(-Double(10 - i) * 60),
                utilization: Double(i) * 6
            )
        }
        let rate = Projector.ewmaBurnRate(samples: samples,
                                          halfLife: 3600,
                                          now: Self.now)
        #expect(rate != nil)
        if let rate {
            #expect(abs(rate - 0.1) < 0.001)
        }
    }
}
