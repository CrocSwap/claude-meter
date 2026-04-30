import SwiftUI

/// Reusable horizontal progress bar for one usage window. Renders as a bar
/// at AGENTS.md-spec colors (green <60, amber 60-85, red >85), with a
/// subtitle showing the percentage and reset countdown.
struct UsageBar: View {
    let title: String
    let window: UsageWindow?
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
                        .fill(threshold.color)
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
        return min(1.0, u / 100)
    }

    private var percentText: String {
        guard let u = window?.utilization else { return "—" }
        return String(format: "%.0f%%", u)
    }

    private var threshold: Threshold {
        guard let u = window?.utilization else { return .neutral }
        return Threshold(utilization: u)
    }

    private var resetText: String {
        guard let resetsAt = window?.resetsAt else {
            return window == nil ? "no data" : "reset time unavailable"
        }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets now" }
        return "resets in \(Self.formatInterval(interval))"
    }

    private static func formatInterval(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: seconds) ?? "—"
    }
}

enum Threshold {
    case neutral, low, medium, high

    init(utilization: Double) {
        switch utilization {
        case ..<60: self = .low
        case 60..<85: self = .medium
        default: self = .high
        }
    }

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
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

#Preview("No data") {
    UsageBar(title: "5 hours", window: nil)
        .padding()
        .frame(width: 280)
}
