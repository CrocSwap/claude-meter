import SwiftUI

/// Speedometer-style upward-opening arc. The left half (0–100% pace) stays
/// monochrome and grows from the left endpoint toward the apex. Above 100%
/// pace, an additional segment continues from apex down the right side,
/// colored terracotta (under 1d dead time) or critical red (over 1d). The
/// dead-time portion's length is capped visually at 3 days. See `docs/ui.md`.
///
/// SwiftUI Path angles are measured clockwise from +x in screen-y-down
/// coordinates: 0° = right, 90° = down, 180° = left, 270° = up. The upper
/// semicircle therefore sweeps from 180° to 360° going counterclockwise
/// (through 270° = up).
struct PacingArc: View {
    /// Pace ratio. Below 1.0 = under pace; 1.0 = at apex; above = into the
    /// dead-time arc on the right side.
    let paceRatio: Double
    /// The outcome from `Projection`. Drives the dead-time arc length and
    /// the apex-dot prominence.
    let outcome: Projection.Outcome?
    /// Drawing color for the 0–100% portion of the arc and the apex dot.
    /// Caller picks black for template rendering, otherwise an explicit
    /// color so it survives the non-template render path.
    var color: Color = .primary

    private let radius: CGFloat = 8
    private let trackLineWidth: CGFloat = 1
    private let foreLineWidth: CGFloat = 2
    /// Visual cap on the dead-time arc (3 days = full quarter sweep).
    private let deadTimeVisualCap: TimeInterval = 3 * 86_400

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 1)

            // Background track — full upper semicircle
            let track = Path { p in
                p.addArc(center: center, radius: radius,
                         startAngle: .degrees(180), endAngle: .degrees(360),
                         clockwise: false)
            }
            context.stroke(
                track,
                with: .color(color.opacity(0.25)),
                style: StrokeStyle(lineWidth: trackLineWidth)
            )

            // Left half: 0–100% pace, always template-tinted
            let leftSweep = min(1.0, max(0, paceRatio)) * 90
            if leftSweep > 0 {
                let leftPath = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180),
                             endAngle: .degrees(180 + leftSweep),
                             clockwise: false)
                }
                context.stroke(
                    leftPath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: foreLineWidth, lineCap: .round)
                )
            }

            // Right half: dead-time arc (over-pace only)
            if let dt = overPaceDeadTime, dt > 0 {
                let fraction = min(1, dt / deadTimeVisualCap)
                let rightSweep = fraction * 90
                let rightColor: Color = dt > 86_400 ? .criticalRed : .terracotta
                let rightPath = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(270),
                             endAngle: .degrees(270 + rightSweep),
                             clockwise: false)
                }
                context.stroke(
                    rightPath,
                    with: .color(rightColor),
                    style: StrokeStyle(lineWidth: foreLineWidth, lineCap: .round)
                )
            }

            // Apex dot — slightly larger when on pace
            let dotRadius: CGFloat = isOnPace ? 1.2 : 0.8
            let apex = CGPoint(x: center.x, y: center.y - radius)
            let dotRect = CGRect(
                x: apex.x - dotRadius, y: apex.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
        .frame(width: 22, height: 14)
    }

    private var overPaceDeadTime: TimeInterval? {
        if case .overPace(let dt) = outcome { return dt }
        return nil
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
