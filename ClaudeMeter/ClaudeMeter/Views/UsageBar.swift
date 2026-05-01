import SwiftUI

/// Reusable horizontal progress bar for one usage window. Renders monochrome
/// (system primary color, template-tinted by macOS) below 85% utilization
/// and `Color.criticalRed` at/above. Fill level alone carries the warning in
/// the 60–85% range — see `docs/brand.md`. Subtitle shows the percentage and
/// reset countdown, with an optional projection annotation underneath.
struct UsageBar: View {
    let title: String
    let window: UsageWindow?
    var projection: Projection? = nil
    var showUnderPaceAnnotation: Bool = true
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
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
            if let line = annotationText {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(annotationColor)
                    .fontWeight(annotationWeight)
            }
        }
    }

    private var fillFraction: Double {
        guard let u = window?.utilization else { return 0 }
        return min(1.0, u / 100)
    }

    private var percentText: String {
        guard let u = window?.utilization else { return "—" }
        return String(format: "%.0f%%", u)
    }

    private var fillColor: Color {
        switch Threshold(utilization: window?.utilization) {
        case .critical: return .criticalRed
        case .normal: return .primary
        case .neutral: return .clear
        }
    }

    private var resetText: String {
        guard let resetsAt = window?.resetsAt else {
            return window == nil ? "no data" : "reset time unavailable"
        }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets now" }
        return "resets in \(DurationFormatter.compact(interval))"
    }

    /// The annotation line beneath the reset countdown — projected dead
    /// time for over-pace, or unused capacity for under-pace. Returns
    /// `nil` when there's nothing to say (no projection, on-pace outcome,
    /// or under-pace with the user's annotation suppressed).
    private var annotationText: String? {
        guard let projection else { return nil }
        let approx = projection.confidence == .low ? "~" : ""
        switch projection.outcome {
        case .onPace:
            return nil
        case .overPace(let deadTime):
            return "locked out \(approx)\(DurationFormatter.compact(deadTime)) before reset"
        case .underPace(let unusedFraction, _):
            guard showUnderPaceAnnotation else { return nil }
            let pct = Int((unusedFraction * 100).rounded())
            return "\(approx)\(pct)% unused at reset"
        }
    }

    private var annotationColor: Color {
        guard let projection else { return .secondary }
        switch projection.outcome {
        case .overPace(let deadTime):
            return deadTime >= 86_400 ? .criticalRed : .primary
        case .underPace, .onPace:
            return .secondary
        }
    }

    private var annotationWeight: Font.Weight {
        guard let projection else { return .regular }
        switch projection.outcome {
        case .overPace: return .semibold
        case .underPace, .onPace: return .regular
        }
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

#Preview("Over pace") {
    UsageBar(title: "7 days",
             window: UsageWindow(utilization: 78.0,
                                 resetsAt: Date().addingTimeInterval(2 * 86400)),
             projection: Projection(
                paceRatio: 1.4,
                confidence: .full,
                outcome: .overPace(deadTime: 6 * 3600)
             ))
        .padding()
        .frame(width: 280)
}

#Preview("Under pace") {
    UsageBar(title: "7 days",
             window: UsageWindow(utilization: 28.0,
                                 resetsAt: Date().addingTimeInterval(4 * 86400)),
             projection: Projection(
                paceRatio: 0.6,
                confidence: .full,
                outcome: .underPace(unusedFraction: 0.30, unusedTime: 12 * 3600)
             ))
        .padding()
        .frame(width: 280)
}

#Preview("No data") {
    UsageBar(title: "5 hours", window: nil)
        .padding()
        .frame(width: 280)
}
