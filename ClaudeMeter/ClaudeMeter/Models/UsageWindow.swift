import Foundation

struct UsageWindow: Decodable, Equatable, Sendable {
    /// Percentage in the range 0.0...100.0 (not a fraction). Anthropic may
    /// return values >= 100 once a window is exhausted; clamp at the view layer.
    let utilization: Double

    /// Window reset time in UTC. The API formats this as ISO 8601 with
    /// microsecond precision (`+00:00` offset). The field is optional even
    /// when the window object is present.
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
