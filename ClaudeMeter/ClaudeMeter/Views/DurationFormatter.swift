import Foundation

/// Human-readable duration formatter used by the menu bar (compact, where
/// space is tight) and the popover (verbose, where space is plentiful).
///
/// Both forms switch units at the same boundaries: minutes for under an
/// hour, hours-and-minutes for under two days, days-and-hours past that.
/// All values are whole-number — no fractional days.
enum DurationFormatter {
    /// Returns e.g. `"47m"`, `"3h"`, `"3h 14m"`, `"2d 7h"`. Used in the
    /// menu bar and other tight surfaces.
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let totalMinutes = total / 60
        let totalHours = totalMinutes / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        if totalHours < 48 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        let d = totalHours / 24
        let h = totalHours % 24
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    /// Returns e.g. `"47 minutes"`, `"3 hours"`, `"3 hours, 14 minutes"`,
    /// `"2 days, 7 hours"`. Used in the popover where the extra clarity
    /// is worth the space.
    static func verbose(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let totalMinutes = total / 60
        let totalHours = totalMinutes / 60
        if totalMinutes < 60 {
            return pluralize(totalMinutes, "minute")
        }
        if totalHours < 48 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            if m == 0 { return pluralize(h, "hour") }
            return "\(pluralize(h, "hour")), \(pluralize(m, "minute"))"
        }
        let d = totalHours / 24
        let h = totalHours % 24
        if h == 0 { return pluralize(d, "day") }
        return "\(pluralize(d, "day")), \(pluralize(h, "hour"))"
    }

    private static func pluralize(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}
