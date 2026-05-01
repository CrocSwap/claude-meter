import SwiftUI
import AppKit

extension Color {
    /// Critical red used when a usage window crosses 85% utilization or when
    /// projected dead time exceeds 1 day. Adaptive: `#D63838` in light mode,
    /// `#E85555` in dark mode. See `docs/brand.md`.
    static let criticalRed = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0xE8 / 255, green: 0x55 / 255, blue: 0x55 / 255, alpha: 1)
            : NSColor(red: 0xD6 / 255, green: 0x38 / 255, blue: 0x38 / 255, alpha: 1)
    })

    /// Terracotta used for the warning dot when the non-displayed window has
    /// 6h–1d projected dead time, and for the pacing-mode dead-time arc in
    /// that range. Adaptive light/dark per `docs/brand.md`.
    static let terracotta = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0xC8 / 255, green: 0x65 / 255, blue: 0x4D / 255, alpha: 1)
            : NSColor(red: 0xB5 / 255, green: 0x56 / 255, blue: 0x3D / 255, alpha: 1)
    })
}
