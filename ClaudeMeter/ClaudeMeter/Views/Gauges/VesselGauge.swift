import SwiftUI

/// Vertical pill gauge that fills bottom-up with utilization. Used directly
/// in popover previews and as the visual content `MenuBarLabel` snapshots
/// into an NSImage. The body is pure SwiftUI shapes — no NSImage wrapping
/// here; that's `MenuBarLabel`'s job for the menu-bar surface.
///
/// See `docs/ui.md` for geometry and `docs/brand.md` for the threshold rule
/// (monochrome below 85%, `criticalRed` at/above).
struct VesselGauge: View {
    let utilization: Double?
    /// Drawing color. The caller picks black for template rendering or
    /// `criticalRed` for explicit critical-state rendering.
    var color: Color = .primary

    private let outerWidth: CGFloat = 6
    private let outerHeight: CGFloat = 14
    private let innerWidth: CGFloat = 4
    private let innerInset: CGFloat = 1.5
    private let cornerRadius: CGFloat = 2.5
    private let innerCornerRadius: CGFloat = 1.25

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(color, lineWidth: 1)

            RoundedRectangle(cornerRadius: innerCornerRadius)
                .fill(color)
                .frame(width: innerWidth, height: fillHeight)
                .padding(.bottom, innerInset)
        }
        .frame(width: outerWidth, height: outerHeight)
    }

    private var fillHeight: CGFloat {
        guard let u = utilization else { return 0 }
        let usable = outerHeight - 2 * innerInset
        let clamped = min(100, max(0, u))
        return CGFloat(clamped / 100) * usable
    }
}

#Preview("0%") {
    VesselGauge(utilization: 0).padding().background(.white)
}

#Preview("42%") {
    VesselGauge(utilization: 42).padding().background(.white)
}

#Preview("78%") {
    VesselGauge(utilization: 78).padding().background(.white)
}

#Preview("Critical 92%") {
    VesselGauge(utilization: 92, color: .criticalRed)
        .padding()
        .background(.white)
}
