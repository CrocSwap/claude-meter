import Foundation

/// Four-state usage threshold the popover bars use to pick fill colors:
///
/// - `.neutral`    — no data (utilization is `nil`) → `Color.clear`
/// - `.normal`     — more than 40% capacity remains → `Color.usageGreen`
/// - `.warning`    — 20–40% capacity remains → `Color.usageYellow`
/// - `.critical`   — 20% or less remains → `Color.criticalRed`
///
/// `init(utilization:)` accepts API-space utilization (0 = fresh, 100 =
/// locked out). A `nil` input becomes `.neutral` so the bar renders an
/// empty track instead of a misleading "fresh" green fill. The numeric
/// constants are in utilization space: `criticalCutoff = 80` ≡ "≤20%
/// remaining"; `warningCutoff = 60` ≡ "≤40% remaining."
enum Threshold {
    case neutral, normal, warning, critical

    /// API-space utilization at which we flip to critical. Equivalent to
    /// "20% capacity remaining."
    static let criticalCutoff: Double = 80.0
    /// API-space utilization at which we flip from healthy to warning.
    /// Equivalent to "40% capacity remaining."
    static let warningCutoff: Double = 60.0

    init(utilization: Double?) {
        guard let u = utilization else { self = .neutral; return }
        if u >= Self.criticalCutoff {
            self = .critical
        } else if u >= Self.warningCutoff {
            self = .warning
        } else {
            self = .normal
        }
    }
}
