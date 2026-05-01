import Foundation

/// Two-state usage threshold the UI uses to pick fill colors. Below 85% we
/// render in the system primary color (template-tinted by macOS); at 85% and
/// above we render in `Color.criticalRed`. There is no amber/medium state —
/// per `docs/brand.md`, fill level alone carries the warning in the 60–85%
/// range and color is reserved for "act now."
enum Threshold {
    case neutral, normal, critical

    /// The boundary is firm at 85%. See `docs/ui.md`.
    static let criticalCutoff: Double = 85.0

    init(utilization: Double?) {
        guard let u = utilization else { self = .neutral; return }
        self = u >= Self.criticalCutoff ? .critical : .normal
    }
}
