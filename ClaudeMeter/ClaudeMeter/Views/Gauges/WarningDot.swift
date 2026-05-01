import SwiftUI

/// Small dot rendered in the upper-right of the gauge area, signaling that
/// the *non-displayed* window has a projected lockout. Asymmetric — never
/// indicates under-pace situations. See `docs/ui.md` and `docs/metrics.md`.
struct WarningDot: View {
    let severity: Severity

    enum Severity: Equatable, Sendable {
        case none
        /// 6h–1d projected dead time on the other window.
        case terracotta
        /// > 1d projected dead time on the other window.
        case red

        /// Map a `Projection` for the *non-tracked* window into a severity.
        init(forNonTracked projection: Projection?) {
            guard let p = projection else { self = .none; return }
            switch p.outcome {
            case .overPace(let dt) where dt > 86_400:
                self = .red
            case .overPace(let dt) where dt > 6 * 3_600:
                self = .terracotta
            default:
                self = .none
            }
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
