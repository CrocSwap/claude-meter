import Foundation

/// Which usage window the menu bar tracks. The other window's state is
/// indicated by the ambient warning dot on the gauge — see `docs/metrics.md`.
enum TrackedWindow: String, CaseIterable, Codable, Sendable {
    case fiveHour
    case sevenDay
}
