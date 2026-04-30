import SwiftUI

/// The text/icon shown in the system menu bar. Renders the higher of the
/// 5h/7d utilization values with a small label noting the binding window.
/// The macOS menu bar tints SwiftUI views automatically; we keep this
/// content monochrome so the system tint reads correctly.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let hasError: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(text)
                .monospacedDigit()
        }
    }

    private var binding: (label: String, utilization: Double)? {
        let candidates: [(String, Double)] = [
            snapshot?.fiveHour.map { ("5h", $0.utilization) },
            snapshot?.sevenDay.map { ("7d", $0.utilization) }
        ].compactMap { $0 }
        return candidates.max(by: { $0.1 < $1.1 })
    }

    private var text: String {
        if hasError && binding == nil { return "—" }
        guard let b = binding else { return "—" }
        return String(format: "%@ %.0f%%", b.label, b.utilization)
    }

    private var iconName: String {
        if hasError { return "exclamationmark.triangle" }
        guard let u = binding?.utilization else { return "gauge.with.dots.needle.0percent" }
        switch Threshold(utilization: u) {
        case .high: return "gauge.with.dots.needle.100percent"
        case .medium: return "gauge.with.dots.needle.67percent"
        case .low, .neutral: return "gauge.with.dots.needle.33percent"
        }
    }
}

#Preview("Low — 5h binding") {
    MenuBarLabel(
        snapshot: UsageSnapshot(
            fiveHour: UsageWindow(utilization: 14.0, resetsAt: Date()),
            sevenDay: UsageWindow(utilization: 5.0, resetsAt: Date())
        ),
        hasError: false
    )
    .padding()
}

#Preview("High — 7d binding") {
    MenuBarLabel(
        snapshot: UsageSnapshot(
            fiveHour: UsageWindow(utilization: 14.0, resetsAt: Date()),
            sevenDay: UsageWindow(utilization: 92.0, resetsAt: Date())
        ),
        hasError: false
    )
    .padding()
}

#Preview("No data") {
    MenuBarLabel(snapshot: nil, hasError: false)
        .padding()
}

#Preview("Error") {
    MenuBarLabel(snapshot: nil, hasError: true)
        .padding()
}
