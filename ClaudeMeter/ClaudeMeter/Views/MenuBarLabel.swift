import SwiftUI
import AppKit

/// The menu-bar label, rendered as a single `Image(nsImage:)`.
///
/// MenuBarExtra collapses multi-element labels (HStack, overlays) to just
/// the first child Image, so we composite everything we want shown — gauge
/// + warning dot + (for pacing mode) the adjacent text — into one SwiftUI
/// view, then snapshot it through `ImageRenderer`. macOS handles tinting
/// when `isTemplate` is true; for critical/warning states we set it false
/// and embed the brand colors directly.
struct MenuBarLabel: View {
    let store: UsageStore
    let settings: AppSettings
    /// Tracked so the rendered NSImage refreshes when the user toggles
    /// light/dark — `monoColor` reads from this and feeds both gauges and
    /// text. Without it, text stays the appearance it was first rendered in.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: rendered)
    }

    private var rendered: NSImage {
        let renderer = ImageRenderer(content: composite)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = isTemplate
        return image
    }

    /// Always false now that we render with explicit appearance-aware
    /// colors (`monoColor`). Template mode would replace those colors with
    /// the menu bar's system tint, which is exactly the behavior that was
    /// causing text to flip from white to black when the gauge flipped red.
    private var isTemplate: Bool { false }

    @ViewBuilder
    private var composite: some View {
        if shouldShowError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(monoColor)
                .padding(2)
        } else {
            ZStack(alignment: .topTrailing) {
                gaugeBody
                if dotSeverity != .none {
                    Circle()
                        .fill(dotSeverity == .red ? Color.criticalRed : Color.terracotta)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -2)
                }
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private var gaugeBody: some View {
        let showUsage = settings.showUsageInMenuBar
        let showPacing = settings.showPacingInMenuBar
        let showPercent = settings.showPercentInMenuBar
        HStack(spacing: 4) {
            if showUsage {
                // Suppress the vessel's splatter when the pacing arc is
                // also visible — the pacing arc carries its own splatter
                // on the right side, and two would crowd the menu bar.
                VesselGauge(
                    utilization: trackedUtil,
                    color: gaugeColor,
                    showMark: !showPacing
                )
                if showPercent {
                    Text(usagePercentText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(monoColor)
                }
            }
            if showPacing {
                PacingArc(
                    paceRatio: trackedProjection?.paceRatio ?? 0,
                    outcome: trackedProjection?.outcome,
                    color: gaugeColor
                )
                if showPercent {
                    Text(pacingPercentText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(monoColor)
                }
            }
        }
    }

    // MARK: - State

    private var shouldShowError: Bool {
        store.lastError != nil && store.snapshot == nil
    }

    private var displaySnapshot: UsageSnapshot? {
        settings.debug.enabled ? settings.debug.syntheticSnapshot() : store.snapshot
    }

    private func displayProjection(for window: TrackedWindow) -> Projection? {
        settings.debug.enabled
            ? settings.debug.syntheticProjection(for: window)
            : store.projection(for: window)
    }

    private var trackedWindow: UsageWindow? {
        switch settings.trackedWindow {
        case .fiveHour: return displaySnapshot?.fiveHour
        case .sevenDay: return displaySnapshot?.sevenDay
        }
    }

    private var trackedUtil: Double? { trackedWindow?.utilization }

    private var trackedProjection: Projection? {
        displayProjection(for: settings.trackedWindow)
    }

    private var nonTrackedProjection: Projection? {
        let other: TrackedWindow = settings.trackedWindow == .fiveHour ? .sevenDay : .fiveHour
        return displayProjection(for: other)
    }

    private var dotSeverity: WarningDot.Severity {
        WarningDot.Severity(forNonTracked: nonTrackedProjection)
    }

    /// Both vessel and pacing arc go red on the same trigger: tracked
    /// pace ratio above 110% (the same boundary the popover radial gauge
    /// uses for its red zone). Vessel is therefore "fill drains, body
    /// turns red when you're projected to lock out early."
    private var isOverPaceCritical: Bool {
        guard let p = trackedProjection else { return false }
        return p.paceRatio > 1.10
    }

    private var gaugeColor: Color {
        isOverPaceCritical ? .criticalRed : monoColor
    }

    /// "Default" color for any non-critical element — matches the menu
    /// bar's text color in the current appearance so the rendered image
    /// looks the same in both template and non-template paths. Without
    /// this, `.black` would render literally and disappear into a dark
    /// menu bar whenever the gauge flips out of template (red, dot).
    private var monoColor: Color {
        colorScheme == .dark ? .white : .black
    }

    // MARK: - Percent labels

    /// Remaining capacity shown to the right of the vessel — matches the
    /// vessel's battery-style fill (the pill drains as you burn tokens,
    /// so the percent counts down with it).
    private var usagePercentText: String {
        guard let u = trackedUtil else { return "—" }
        let remaining = max(0, 100 - u)
        return "\(Int(remaining.rounded()))%"
    }

    /// Pace ratio shown to the right of the pacing arc. Replaces the old
    /// "on pace" / "+Xh" conditional text — always a raw percent so the
    /// label stays consistent across zones.
    private var pacingPercentText: String {
        guard let projection = trackedProjection else { return "—" }
        return "\(Int((projection.paceRatio * 100).rounded()))%"
    }

}
