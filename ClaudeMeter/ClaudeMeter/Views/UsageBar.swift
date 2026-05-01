import SwiftUI

/// Reusable horizontal bar for one usage window, displayed in *remaining*
/// terms (battery-style): the bar shrinks as the user burns through the
/// window. Color reflects how much room is left — green above 40%, yellow
/// 20–40%, red at or below 20%. See `docs/brand.md`. Subtitle shows
/// "X% left" plus the reset countdown.
struct UsageBar: View {
    let title: String
    let window: UsageWindow?
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillColor)
                        .frame(width: max(0, min(1, fillFraction)) * geo.size.width)
                }
            }
            .frame(height: 6)
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var fillFraction: Double {
        guard let u = window?.utilization else { return 0 }
        let remaining = 100 - u
        return min(1.0, max(0, remaining / 100))
    }

    private var percentText: String {
        guard let u = window?.utilization else { return "—" }
        return String(format: "%.0f%% left", max(0, 100 - u))
    }

    private var fillColor: Color {
        switch Threshold(utilization: window?.utilization) {
        case .critical: return .criticalRed
        case .warning: return .usageYellow
        case .normal: return .usageGreen
        case .neutral: return .clear
        }
    }

    private var resetText: String {
        guard let resetsAt = window?.resetsAt else {
            return window == nil ? "no data" : "reset time unavailable"
        }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets now" }
        return "resets in \(DurationFormatter.verbose(interval))"
    }

}

#Preview("Low") {
    UsageBar(title: "5 hours",
             window: UsageWindow(utilization: 14.0,
                                 resetsAt: Date().addingTimeInterval(3 * 3600)))
        .padding()
        .frame(width: 280)
}

#Preview("Medium") {
    UsageBar(title: "7 days",
             window: UsageWindow(utilization: 65.0,
                                 resetsAt: Date().addingTimeInterval(2 * 86400)))
        .padding()
        .frame(width: 280)
}

#Preview("High") {
    UsageBar(title: "5 hours",
             window: UsageWindow(utilization: 92.0,
                                 resetsAt: Date().addingTimeInterval(45 * 60)))
        .padding()
        .frame(width: 280)
}

#Preview("No data") {
    UsageBar(title: "5 hours", window: nil)
        .padding()
        .frame(width: 280)
}
