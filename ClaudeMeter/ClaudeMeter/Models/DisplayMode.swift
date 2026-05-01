import Foundation

/// How the menu bar gauge renders the tracked window. User-selectable via
/// the settings panel. See `docs/ui.md` for the full visual contract.
///
/// Pending v1 work — only `.vessel` is currently rendered. Pacing and
/// numeric modes land alongside the custom-rendered gauge.
enum DisplayMode: String, CaseIterable, Codable, Sendable {
    /// Vertical pill that fills bottom-up with utilization. Default.
    case vessel
    /// Speedometer arc tracking pace ratio + projected dead time.
    case pacing
    /// Plain percentage text. No graphical gauge.
    case numeric
}

/// Which usage window the menu bar tracks. The other window's state is
/// indicated by the ambient warning dot on the gauge — see `docs/metrics.md`.
enum TrackedWindow: String, CaseIterable, Codable, Sendable {
    case fiveHour
    case sevenDay
}
