import SwiftUI

/// Small dot rendered in the upper-right of the gauge area, signaling that
/// the *non-displayed* window has a projected lockout. Asymmetric — never
/// indicates under-pace situations. See `docs/ui.md` and `docs/metrics.md`.
struct WarningDot: View {
    let severity: Severity

    enum Severity: Equatable, Sendable {
        case none
        /// Other window's pace ratio in 110–130% — heads up, it just
        /// crossed into the gauge's red zone.
        case terracotta
        /// Other window's pace ratio above 130% — severe overshoot,
        /// well into the red zone.
        case red

        /// Map a `Projection` for the *non-tracked* window into a severity.
        /// Aligned with the gauge body's 110% red trigger so the dot lights
        /// up exactly when the other window's gauge would be red.
        init(forNonTracked projection: Projection?) {
            guard let p = projection else { self = .none; return }
            if p.paceRatio > 1.30 { self = .red }
            else if p.paceRatio > 1.10 { self = .terracotta }
            else { self = .none }
        }
    }

    var body: some View {
        if severity != .none {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }

    private var color: Color {
        switch severity {
        case .red: return .criticalRed
        case .terracotta: return .terracotta
        case .none: return .clear
        }
    }
}

#Preview("Terracotta") {
    WarningDot(severity: .terracotta).padding().background(.background)
}

#Preview("Red") {
    WarningDot(severity: .red).padding().background(.background)
}

#Preview("None") {
    WarningDot(severity: .none)
        .frame(width: 22, height: 22)
        .background(.background)
}
