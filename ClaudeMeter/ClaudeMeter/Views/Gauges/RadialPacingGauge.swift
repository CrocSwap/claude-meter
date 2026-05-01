import SwiftUI

/// Radial speedometer-style gauge for pacing. Solid green arc from 0–100%
/// pace, transitioning into an amber→red gradient for over-pace (100–150%).
/// A needle pivots from the bottom-center to the current pace ratio,
/// color-matched to the zone it points into.
///
/// Conceptually distinct from the usage bars: pacing is a *rate* metric
/// (current burn vs. sustainable burn), not a *level* metric. The value
/// can exceed 100% — the asymmetric color split conveys the penalty
/// shape directly.
///
/// The popover renders a single unified status sentence beneath both
/// gauges (see `UsagePopover.pacingStatusText`); this view contains only
/// the label and the dial itself.
struct RadialPacingGauge: View {
    let label: String
    let projection: Projection?

    /// Visual maximum on the arc — pace ratios above this push the
    /// needle into the off-gauge overflow zone (see `overflowDegrees`).
    private let arcMax: Double = 1.5
    /// How far past the right end of the arc the needle is allowed to
    /// swing when the pace ratio runs off the gauge. Reads as "the
    /// engine's running so hot the needle's pinned past the dial."
    private let overflowDegrees: Double = 15
    /// Pace-ratio overshoot at which the overflow needle reaches its
    /// maximum 15° excursion. A burst of e.g. 200% pace lands fully
    /// off-gauge; anything beyond just stays pinned there.
    private let overflowSaturation: Double = 0.5
    /// Pace ratio at which the gauge turns from green to amber. Aligned
    /// with the popover's "under-utilized → on-target" status barrier so
    /// the gauge color and the status sentence change in lockstep.
    private let underBoundary: Double = 0.85
    /// Pace ratio at which the gauge turns from amber to red. Aligned
    /// with the "on-target → burnout" status barrier.
    private let burnoutBoundary: Double = 1.10

    private let arcWidth: CGFloat = 110
    private let arcHeight: CGFloat = 76
    private let strokeWidth: CGFloat = 10
    /// Vertical room reserved below the gauge center for the off-gauge
    /// needle when pace ratio exceeds `arcMax`. The needle pivots at
    /// `size.height - centerInset` so the overflow swing has space to
    /// land instead of getting clipped by the canvas bounds.
    private let centerInset: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)

            arcCanvas
                .frame(width: arcWidth, height: arcHeight)

            Text(percentText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .frame(width: arcWidth)
    }

    private var percentText: String {
        guard let p = projection else { return "—" }
        return "\(Int((p.paceRatio * 100).rounded()))%"
    }

    private var arcCanvas: some View {
        Canvas { context, size in
            // Arc is the upper semicircle of a circle whose center sits
            // `centerInset` above the canvas bottom — leaving room below
            // for the needle when it swings off the right end of the
            // gauge.
            let center = CGPoint(x: size.width / 2, y: size.height - centerInset)
            let radius = min(size.width / 2, size.height - centerInset) - strokeWidth / 2 - 1

            let greenEnd = arcDegrees(for: underBoundary)    // ~282°
            let amberEnd = arcDegrees(for: burnoutBoundary)  // ~312°

            // Green zone — under utilized (0–85%).
            stroke(arcFrom: 180, to: greenEnd,
                   center: center, radius: radius,
                   shading: .color(.usageGreen),
                   cap: .round, in: context)

            // Amber zone — on target (85–110%). Slight overlap on each
            // side keeps adjacent zones butting cleanly without sub-
            // pixel seams.
            stroke(arcFrom: greenEnd - 0.3, to: amberEnd + 0.3,
                   center: center, radius: radius,
                   shading: .color(.pacingAmber),
                   cap: .butt, in: context)

            // Red zone — burnout (110–150%).
            stroke(arcFrom: amberEnd, to: 360,
                   center: center, radius: radius,
                   shading: .color(.criticalRed),
                   cap: .round, in: context)

            // Needle — drawn from a point just outside the pivot to a
            // point just inside the arc, so the line doesn't intersect
            // the pivot ring or overshoot the zone band.
            let needleStart = arcPoint(center: center, radius: 5, degrees: needleDegrees)
            let needleEnd = arcPoint(center: center,
                                     radius: radius - strokeWidth / 2 - 2.5,
                                     degrees: needleDegrees)
            var needlePath = Path()
            needlePath.move(to: needleStart)
            needlePath.addLine(to: needleEnd)
            context.stroke(
                needlePath,
                with: .color(valueColor),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )

            // Pivot ring
            let pivotR: CGFloat = 4
            let pivotRect = CGRect(
                x: center.x - pivotR, y: center.y - pivotR,
                width: pivotR * 2, height: pivotR * 2
            )
            context.stroke(
                Path(ellipseIn: pivotRect),
                with: .color(valueColor),
                lineWidth: 1.4
            )
        }
    }

    private func stroke(arcFrom startDeg: Double, to endDeg: Double,
                        center: CGPoint, radius: CGFloat,
                        shading: GraphicsContext.Shading,
                        cap: CGLineCap,
                        in context: GraphicsContext) {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(endDeg),
                    clockwise: false)
        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: cap)
        )
    }

    /// Maps a pace ratio onto the arc's angular space. The arc spans
    /// [180°, 360°] in SwiftUI's screen-y-down coordinates, where 180° is
    /// the left endpoint, 270° is the apex, and 360° is the right endpoint.
    private func arcDegrees(for ratio: Double) -> Double {
        let clamped = max(0, min(arcMax, ratio))
        return 180 + (clamped / arcMax) * 180
    }

    private func arcPoint(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let rad = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(rad) * radius,
            y: center.y + sin(rad) * radius
        )
    }

    private var needleDegrees: Double {
        guard let p = projection else { return 180 }
        if p.paceRatio <= arcMax {
            return arcDegrees(for: p.paceRatio)
        }
        let overshoot = min(overflowSaturation, p.paceRatio - arcMax)
        let extra = (overshoot / overflowSaturation) * overflowDegrees
        return 360 + extra
    }

    private var paceRatio: Double { projection?.paceRatio ?? 0 }

    private var valueColor: Color {
        guard projection != nil else { return .secondary }
        if paceRatio < underBoundary { return .usageGreen }
        if paceRatio <= burnoutBoundary { return .pacingAmber }
        return .criticalRed
    }
}

#Preview("Under pace 62%") {
    RadialPacingGauge(
        label: "Session",
        projection: Projection(paceRatio: 0.62, confidence: .full,
                               outcome: .underPace(unusedFraction: 0.4, unusedTime: 7200))
    )
    .padding()
    .background(.background)
}

#Preview("On target 94%") {
    RadialPacingGauge(
        label: "Weekly",
        projection: Projection(paceRatio: 0.94, confidence: .full, outcome: .onPace)
    )
    .padding()
    .background(.background)
}

#Preview("Over pace 118% / 0.9d early") {
    RadialPacingGauge(
        label: "Hot example",
        projection: Projection(paceRatio: 1.18, confidence: .full,
                               outcome: .overPace(deadTime: 0.9 * 86400))
    )
    .padding()
    .background(.background)
}

#Preview("No projection") {
    RadialPacingGauge(label: "Session", projection: nil)
        .padding()
        .background(.background)
}
