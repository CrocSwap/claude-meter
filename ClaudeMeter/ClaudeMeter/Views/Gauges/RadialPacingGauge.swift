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

    /// Visual maximum on the arc — pace ratios above this are clamped to
    /// the right end of the gauge.
    private let arcMax: Double = 1.5
    /// Boundary between the green safe zone and the amber→red over-pace
    /// zone — also where the needle's color shifts.
    private let onTargetBoundary: Double = 1.00
    /// Above this, the needle goes red rather than amber. Mirrors the
    /// urgency escalation along the gradient itself.
    private let warningBoundary: Double = 1.05

    private let arcWidth: CGFloat = 110
    private let arcHeight: CGFloat = 64
    private let strokeWidth: CGFloat = 10

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
            // Arc is the upper semicircle of a circle whose center sits at
            // the bottom-center of the canvas.
            let center = CGPoint(x: size.width / 2, y: size.height - 2)
            let radius = min(size.width / 2, size.height) - strokeWidth / 2 - 1

            let safeEnd = arcDegrees(for: onTargetBoundary) // ~300°

            // Safe zone — solid green from 0% all the way to 100%.
            stroke(arcFrom: 180, to: safeEnd,
                   center: center, radius: radius,
                   shading: .color(.usageGreen),
                   cap: .round, in: context)

            // Over-pace zone — amber → red gradient from 100% to 150%.
            // Linear gradient from the segment start (top-center) to the
            // end (right-center) approximates the conic sweep over the
            // ~60° segment well enough.
            let overStart = arcPoint(center: center, radius: radius, degrees: safeEnd)
            let overEnd = arcPoint(center: center, radius: radius, degrees: 360)
            stroke(arcFrom: safeEnd, to: 360,
                   center: center, radius: radius,
                   shading: .linearGradient(
                        Gradient(colors: [.pacingAmber, .criticalRed]),
                        startPoint: overStart,
                        endPoint: overEnd),
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
        return arcDegrees(for: p.paceRatio)
    }

    private var paceRatio: Double { projection?.paceRatio ?? 0 }

    private var valueColor: Color {
        guard projection != nil else { return .secondary }
        if paceRatio < onTargetBoundary { return .usageGreen }
        if paceRatio < warningBoundary { return .pacingAmber }
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
