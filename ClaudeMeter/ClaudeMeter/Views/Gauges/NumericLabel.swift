import SwiftUI

/// Plain percentage text mode. No graphical gauge. Renders monochrome
/// until 85%, then `criticalRed`. See `docs/ui.md`.
struct NumericLabel: View {
    let utilization: Double?

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(color)
    }

    private var text: String {
        guard let u = utilization else { return "—" }
        return "\(Int(u.rounded()))%"
    }

    private var color: Color {
        Threshold(utilization: utilization) == .critical ? .criticalRed : .primary
    }
}

#Preview("Normal 42%") {
    NumericLabel(utilization: 42).padding().background(.background)
}

#Preview("Critical 92%") {
    NumericLabel(utilization: 92).padding().background(.background)
}

#Preview("No data") {
    NumericLabel(utilization: nil).padding().background(.background)
}
