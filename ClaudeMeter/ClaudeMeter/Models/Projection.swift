import Foundation

/// The result of running `Projector` on a window. The popover renders the
/// annotation directly off this value; presence/absence of annotation is
/// driven by `Projector` returning `nil` (suppressed) or a `Projection`.
///
/// See `docs/metrics.md` for the framing rules the views apply.
struct Projection: Equatable, Sendable {
    /// Pace ratio: current utilization divided by expected utilization at
    /// this point in the window. > 1.0 over pace, < 1.0 under pace.
    let paceRatio: Double

    /// How confident the projection is. Drives visual weight of the
    /// annotation (lighter color, leading `~`) when `.low`.
    let confidence: Confidence

    /// What the popover should say.
    let outcome: Outcome

    enum Confidence: Sendable {
        /// Show with reduced visual weight and a leading `~`. Triggered
        /// when current utilization is in the 10–25% range.
        case low
        /// Show at full visual weight. Utilization >= 25%.
        case full
    }

    enum Outcome: Equatable, Sendable {
        /// Pace ratio is in [0.95, 1.05] — annotation is suppressed.
        case onPace
        /// User will exhaust capacity before reset. `deadTime` is how long
        /// they'll be locked out (seconds).
        case overPace(deadTime: TimeInterval)
        /// User will not exhaust capacity by reset. `unusedFraction` is the
        /// share of cap that goes unused (0...1); `unusedTime` is the
        /// equivalent runway in seconds at the current burn rate.
        case underPace(unusedFraction: Double, unusedTime: TimeInterval)
    }
}
