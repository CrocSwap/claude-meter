import Foundation

/// Compact human-readable duration formatter used by the popover for both
/// reset countdowns and projected dead-time annotations.
///
/// Per `docs/metrics.md` the threshold for switching units is firm:
/// minutes for under an hour, hours-and-minutes for under two days, days
/// (one decimal) past that.
enum DurationFormatter {
    /// Returns e.g. `"47m"`, `"3h"`, `"3h 14m"`, `"3.2d"`.
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let totalMinutes = total / 60
        let totalHours = Double(total) / 3600
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        } else if totalHours < 48 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        } else {
            let days = totalHours / 24
            return String(format: "%.1fd", days)
        }
    }
}
