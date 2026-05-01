import SwiftUI

/// 8-rayed splatter mark, a tiny approximation of Claude's brand burst.
/// Drawn with `Canvas` so it stays crisp at the 3–5pt sizes used as a
/// brand watermark on `VesselGauge`. Color is template-friendly — pass
/// `.primary` for menu-bar template tinting, or any explicit color.
struct ClaudeMark: View {
    var color: Color = .primary
    var size: CGFloat = 4
    var rayWidth: CGFloat = 0.7

    var body: some View {
        Canvas { context, canvas in
            let cx = canvas.width / 2
            let cy = canvas.height / 2
            let r = min(canvas.width, canvas.height) / 2
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let x = cx + CGFloat(cos(angle)) * r
                let y = cy + CGFloat(sin(angle)) * r
                var path = Path()
                path.move(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: x, y: y))
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: rayWidth, lineCap: .round)
                )
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        ClaudeMark(size: 4)
        ClaudeMark(size: 8)
        ClaudeMark(size: 16)
        ClaudeMark(size: 32, rayWidth: 2)
    }
    .padding()
    .background(.background)
}
