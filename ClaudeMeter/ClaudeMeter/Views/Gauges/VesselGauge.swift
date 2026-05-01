import SwiftUI

/// Vertical pill gauge that displays *remaining* capacity (battery-style):
/// fills bottom-up with `100 - utilization`, so a fresh window is full and
/// the pill drains as the user burns through tokens. The `utilization`
/// input is in API-space (0 = fresh, 100 = locked out); inversion happens
/// here in the display layer. Used directly in popover previews and as the
/// visual content `MenuBarLabel` snapshots into an NSImage.
///
/// See `docs/ui.md` for geometry and `docs/brand.md` for the threshold rule
/// (monochrome until ≤15% remaining, `criticalRed` below).
struct VesselGauge: View {
    let utilization: Double?
    /// Drawing color. The caller picks black for template rendering or
    /// `criticalRed` for explicit critical-state rendering.
    var color: Color = .primary
    /// Whether to render the brand splatter mark in the bottom-right
    /// corner. Off when the menu bar shows vessel + pacing side by side
    /// — the pacing arc carries the splatter on its outer side, so two
    /// would be redundant.
    var showMark: Bool = true

    private let outerWidth: CGFloat = 9
    private let outerHeight: CGFloat = 16
    private let innerWidth: CGFloat = 6
    private let innerInset: CGFloat = 2
    private let cornerRadius: CGFloat = 3
    private let innerCornerRadius: CGFloat = 1.5
    private let strokeWidth: CGFloat = 1.25
    /// Floor on the rendered inner-fill height when remaining > 0, so a
    /// nearly-empty pill doesn't look identical to a fully-empty one.
    private let minVisibleFill: CGFloat = 1.75
    /// Brand splatter overlaid at the bottom-right corner so the gauge
    /// reads as "battery for Claude" rather than a generic level indicator.
    private let markSize: CGFloat = 8
    /// How far the mark's center sits beyond the pill's bottom-right
    /// corner. Keeps the mark mostly outside the fill area while still
    /// feeling attached.
    private let markPokeOut: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color, lineWidth: strokeWidth)

                RoundedRectangle(cornerRadius: innerCornerRadius)
                    .fill(color)
                    .frame(width: innerWidth, height: fillHeight)
                    .padding(.bottom, innerInset)
            }
            .frame(width: outerWidth, height: outerHeight)

            if showMark {
                ClaudeMark(color: color, size: markSize, rayWidth: 1.2)
                    .offset(
                        x: outerWidth - markSize / 2 + markPokeOut,
                        y: outerHeight - markSize / 2 + markPokeOut
                    )
            }
        }
        .frame(
            width: showMark ? outerWidth + markSize / 2 + markPokeOut : outerWidth,
            height: showMark ? outerHeight + markSize / 2 + markPokeOut : outerHeight,
            alignment: .topLeading
        )
    }

    private var fillHeight: CGFloat {
        guard let u = utilization else { return 0 }
        let remaining = 100 - min(100, max(0, u))
        if remaining <= 0 { return 0 }
        let usable = outerHeight - 2 * innerInset
        let raw = CGFloat(remaining / 100) * usable
        return max(minVisibleFill, raw)
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
