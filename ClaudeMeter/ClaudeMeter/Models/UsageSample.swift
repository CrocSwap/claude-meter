import Foundation

/// One observation of a window's utilization at a point in time. The store
/// keeps a rolling buffer of these per window; `Projector` consumes the
/// buffer to compute pace and projected dead time. See `docs/metrics.md`.
struct UsageSample: Equatable, Sendable {
    let timestamp: Date
    /// Percentage in 0...100, matching `UsageWindow.utilization`.
    let utilization: Double
}
