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

    /// True when nothing in the composite needs explicit color — the image
    /// can be a template and macOS auto-tints it. False when we have a
    /// critical-red gauge, an over-pace dead-time arc, or a warning dot.
    private var isTemplate: Bool {
        if shouldShowError { return true }
        if isCritical { return false }
        if hasOverPaceColor { return false }
        if dotSeverity != .none { return false }
        return true
    }

    @ViewBuilder
    private var composite: some View {
        if shouldShowError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black)
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
        switch settings.displayMode {
        case .vessel:
            VesselGauge(utilization: trackedUtil, color: gaugeColor)
        case .pacing:
            HStack(spacing: 3) {
                PacingArc(
                    paceRatio: trackedProjection?.paceRatio ?? 0,
                    outcome: trackedProjection?.outcome,
                    color: gaugeColor
                )
                Text(pacingText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(pacingTextColor)
            }
        case .numeric:
            Text(numericText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(gaugeColor)
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

    private var isCritical: Bool {
        guard let u = trackedUtil else { return false }
        return Threshold(utilization: u) == .critical
    }

    private var hasOverPaceColor: Bool {
        if case .overPace = trackedProjection?.outcome { return true }
        return false
    }

    private var gaugeColor: Color {
        isCritical ? .criticalRed : .black
    }

    // MARK: - Pacing-mode label

    private var pacingText: String {
        guard let util = trackedUtil,
              util >= Projector.minimumUtilization,
              let projection = trackedProjection else { return "—" }
        let pace = projection.paceRatio
        if pace >= 0.95 && pace <= 1.05 {
            return "on pace"
        }
        if pace > 1.05, case .overPace(let dt) = projection.outcome {
            return "+\(DurationFormatter.compact(dt))"
        }
        return "\(Int((pace * 100).rounded()))% pace"
    }

    private var pacingTextColor: Color {
        guard let projection = trackedProjection else { return .black }
        if case .overPace(let dt) = projection.outcome {
            return dt > 86_400 ? .criticalRed : .terracotta
        }
        return .black
    }

    private var numericText: String {
        guard let u = trackedUtil else { return "—" }
        let remaining = max(0, 100 - u)
        return "\(Int(remaining.rounded()))%"
    }
}
