import Foundation
import Testing
@testable import ClaudeMeter

@Suite("Projector")
struct ProjectorTests {

    static let now = Date(timeIntervalSince1970: 1_777_577_933)
    static let fiveHourDuration: TimeInterval = 5 * 3600
    static let sevenDayDuration: TimeInterval = 7 * 86400

    @Test("Zero utilization → nil")
    func zeroUtilization() {
        let window = UsageWindow(utilization: 0, resetsAt: Self.now.addingTimeInterval(3600))
        let p = Projector.project(window: window,
                                  windowDuration: Self.fiveHourDuration,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Missing resetsAt → nil")
    func missingResetsAt() {
        let window = UsageWindow(utilization: 40, resetsAt: nil)
        let p = Projector.project(window: window,
                                  windowDuration: Self.fiveHourDuration,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Reset already passed → nil")
    func resetInPast() {
        let window = UsageWindow(utilization: 40, resetsAt: Self.now.addingTimeInterval(-60))
        let p = Projector.project(window: window,
                                  windowDuration: Self.fiveHourDuration,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("Window hasn't started yet (no elapsed time) → nil")
    func noElapsedTime() {
        // resetsAt is exactly windowDuration in the future → elapsed = 0.
        let window = UsageWindow(utilization: 1, resetsAt: Self.now.addingTimeInterval(Self.fiveHourDuration))
        let p = Projector.project(window: window,
                                  windowDuration: Self.fiveHourDuration,
                                  now: Self.now)
        #expect(p == nil)
    }

    @Test("On-pace: 50% used at 50% elapsed → ratio 1.0, outcome .onPace")
    func onPace() {
        // 5h window, 2.5h elapsed (2.5h until reset), 50% used.
        // Linear projection lands at 100%, well within ±5pp band.
        let window = UsageWindow(utilization: 50, resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        guard let p = Projector.project(window: window,
                                        windowDuration: Self.fiveHourDuration,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 1.0) < 0.001)
        #expect(p.outcome == Projection.Outcome.onPace)
    }

    @Test("Over-pace: 80% used at 40% elapsed → ratio 2.0, dead time 2.5h")
    func overPace() {
        // 5h window, 2h elapsed (3h until reset), 80% used.
        // Burn rate = 40 pp/h; hits 100% in 0.5h; dead time = 3 - 0.5 = 2.5h.
        let window = UsageWindow(utilization: 80, resetsAt: Self.now.addingTimeInterval(3 * 3600))
        guard let p = Projector.project(window: window,
                                        windowDuration: Self.fiveHourDuration,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 2.0) < 0.001)
        if case .overPace(let deadTime) = p.outcome {
            #expect(abs(deadTime - 2.5 * 3600) < 1)
        } else {
            Issue.record("expected overPace outcome")
        }
    }

    @Test("Under-pace: 10% used at 50% elapsed → ratio 0.2, unused fraction 0.8")
    func underPace() {
        // 5h window, 2.5h elapsed (2.5h until reset), 10% used.
        // Linear projection lands at 20% — 80% unused.
        let window = UsageWindow(utilization: 10, resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        guard let p = Projector.project(window: window,
                                        windowDuration: Self.fiveHourDuration,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 0.2) < 0.001)
        if case .underPace(let unusedFraction, let unusedTime) = p.outcome {
            #expect(abs(unusedFraction - 0.8) < 0.001)
            #expect(unusedTime > 0)
        } else {
            Issue.record("expected underPace outcome")
        }
    }

    @Test("Just over the on-pace band still classifies as overPace")
    func justOverBand() {
        // Project to ~106% — outside the ±5pp band.
        // 5h window, 2.5h elapsed, 53% used → projects to 106%.
        let window = UsageWindow(utilization: 53, resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        guard let p = Projector.project(window: window,
                                        windowDuration: Self.fiveHourDuration,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        if case .overPace = p.outcome {
            // expected
        } else {
            Issue.record("expected overPace outcome, got \(p.outcome)")
        }
    }

    @Test("Weekly window: 50% used at 50% elapsed → on pace")
    func weeklyOnPace() {
        // 7d window, 3.5d elapsed (3.5d until reset), 50% used.
        let window = UsageWindow(utilization: 50, resetsAt: Self.now.addingTimeInterval(3.5 * 86400))
        guard let p = Projector.project(window: window,
                                        windowDuration: Self.sevenDayDuration,
                                        now: Self.now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 1.0) < 0.001)
        #expect(p.outcome == Projection.Outcome.onPace)
    }
}
