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

    /// Healthy "you've got headroom" green for the popover usage bars.
    /// Tracks Apple's `systemGreen` so it feels native against macOS chrome.
    static let usageGreen = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
            : NSColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
    })

    /// Mid-range "starting to thin out" yellow for the popover usage bars,
    /// shown in the 20–40% remaining band. Tracks Apple's `systemYellow`.
    static let usageYellow = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
            : NSColor(red: 0xFF / 255, green: 0xCC / 255, blue: 0x00 / 255, alpha: 1)
    })

    /// Muted slate gray for the under-pace zone of radial pacing gauges.
    /// Communicates "fine, just FYI" without being invisible against the
    /// popover background.
    static let pacingSlate = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
            : NSColor(red: 0x4A / 255, green: 0x55 / 255, blue: 0x68 / 255, alpha: 1)
    })

    /// Amber that anchors the start of the over-pace gradient on radial
    /// pacing gauges. Pairs with `criticalRed` to span the 100–150% danger
    /// zone — gradient escalates urgency as the needle moves further right.
    static let pacingAmber = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)
            : NSColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255, alpha: 1)
    })
}
