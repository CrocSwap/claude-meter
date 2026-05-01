import SwiftUI

/// Speedometer-style upward-opening arc for the menu bar. The fill grows
/// from the left endpoint and the on-pace target sits at the *right end*
/// of the arc — intentionally different geometry from the popover's
/// radial gauges (which target ~100% near the apex on a 0–150% scale).
/// Here the entire arc represents 0–100% pace; over-pace is communicated
/// via the menu-bar warning dot and the adjacent text, not visually on
/// the arc. The arc stops just shy of the right endpoint so the Claude
/// splatter mark in the bottom-right corner has clearance.
///
/// SwiftUI Path angles are measured clockwise from +x in screen-y-down
/// coordinates: 0° = right, 90° = down, 180° = left, 270° = up. The upper
/// semicircle therefore sweeps from 180° to 360° going counterclockwise
/// (through 270° = up).
struct PacingArc: View {
    /// Pace ratio. 0 = empty arc; 1.0 = full arc, target dot lit. Values
    /// above 1.0 are clamped visually (the arc stays full).
    let paceRatio: Double
    /// The outcome from `Projection`. Drives the on-pace dot prominence.
    let outcome: Projection.Outcome?
    /// Drawing color for the arc and the target dot. Caller picks black
    /// for template rendering, otherwise an explicit color so it
    /// survives the non-template render path.
    var color: Color = .primary

    private let radius: CGFloat = 8
    private let trackLineWidth: CGFloat = 1
    private let foreLineWidth: CGFloat = 2
    /// How far short of the right endpoint (360°) the arc stops, so the
    /// brand splatter mark in the bottom-right corner has visual
    /// breathing room.
    private let splatterClearanceDeg: Double = 12
    /// Where the on-pace target dot lands as a fraction of the arc's
    /// visible sweep. 0.75 puts 100% pace at three-quarters along — the
    /// final quarter visually represents over-pace, clamped at the
    /// splatter boundary.
    private let targetFraction: Double = 0.75
    /// Arc's own drawing canvas, before the brand mark is overlaid.
    private let arcWidth: CGFloat = 22
    private let arcHeight: CGFloat = 14
    /// Brand splatter mark, matching the size and weight used on `VesselGauge`.
    private let markSize: CGFloat = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            arcCanvas
                .frame(width: arcWidth, height: arcHeight)

            ClaudeMark(color: color, size: markSize, rayWidth: 1.2)
                .offset(x: arcWidth - markSize / 2, y: arcHeight - markSize / 2)
        }
        .frame(
            width: arcWidth + markSize / 2,
            height: arcHeight + markSize / 2,
            alignment: .topLeading
        )
    }

    private var arcCanvas: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 1)

            // Visible arc spans the upper semicircle minus the splatter
            // clearance on the right.
            let arcEndDeg = 360.0 - splatterClearanceDeg
            let arcSweep = arcEndDeg - 180.0
            // Pace ratio at which the arc is fully filled. 100% lands at
            // `targetFraction` of the sweep; the rest is over-pace runway.
            let arcMax = 1.0 / targetFraction
            let targetDeg = 180.0 + targetFraction * arcSweep

            // Background track — full visible arc.
            let track = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(180),
                         endAngle: .degrees(arcEndDeg),
                         clockwise: false)
            }
            context.stroke(
                track,
                with: .color(color.opacity(0.25)),
                style: StrokeStyle(lineWidth: trackLineWidth)
            )

            // Foreground fill. 0–100% covers the safe zone (up to the
            // target dot); over-pace continues into the final quarter
            // and clamps at the splatter boundary.
            let clamped = min(arcMax, max(0, paceRatio))
            let foreSweep = (clamped / arcMax) * arcSweep
            if foreSweep > 0 {
                let forePath = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180),
                             endAngle: .degrees(180 + foreSweep),
                             clockwise: false)
                }
                context.stroke(
                    forePath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: foreLineWidth, lineCap: .round)
                )
            }

            // Target dot — marks the 100% landing. Slightly larger when
            // actually on pace.
            let dotRadius: CGFloat = isOnPace ? 1.2 : 0.8
            let targetRad = targetDeg * .pi / 180
            let target = CGPoint(
                x: center.x + cos(targetRad) * radius,
                y: center.y + sin(targetRad) * radius
            )
            let dotRect = CGRect(
                x: target.x - dotRadius, y: target.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    private var isOnPace: Bool {
        if case .onPace = outcome { return true }
        return false
    }
}

#Preview("Under pace 0.6") {
    PacingArc(paceRatio: 0.6, outcome: .underPace(unusedFraction: 0.3, unusedTime: 12 * 3600))
        .padding().background(.background)
}

#Preview("On pace") {
    PacingArc(paceRatio: 1.0, outcome: .onPace)
        .padding().background(.background)
}

#Preview("Over pace, terracotta dead time 8h") {
    PacingArc(paceRatio: 1.4, outcome: .overPace(deadTime: 8 * 3600))
        .padding().background(.background)
}

#Preview("Over pace, red dead time 2d") {
    PacingArc(paceRatio: 1.8, outcome: .overPace(deadTime: 2 * 86_400))
        .padding().background(.background)
}
