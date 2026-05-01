import SwiftUI

/// The click-to-reveal panel shown when the user is signed in. Observes
/// `UsageStore` directly. The owner of the store is responsible for
/// passing in callbacks for refresh / quit / sign-out actions.
struct UsagePopover: View {
    let store: UsageStore
    let settings: AppSettings
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageBar(
                title: "Session",
                window: displaySnapshot?.fiveHour,
                projection: displayProjection(for: .fiveHour),
                showUnderPaceAnnotation: settings.showUnderPaceAnnotation
            )
            UsageBar(
                title: "Weekly",
                window: displaySnapshot?.sevenDay,
                projection: displayProjection(for: .sevenDay),
                showUnderPaceAnnotation: settings.showUnderPaceAnnotation
            )

            Divider()

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    RadialPacingGauge(
                        label: "Session",
                        projection: displayProjection(for: .fiveHour)
                    )
                    RadialPacingGauge(
                        label: "Weekly",
                        projection: displayProjection(for: .sevenDay)
                    )
                }
                if let status = pacingStatus {
                    Text(status.text)
                        .font(.footnote)
                        .foregroundStyle(status.color)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(footerText(now: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if displayApiUnavailable {
                            Text("API currently unavailable")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        if let message = signInMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings…")
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }

            HStack {
                Spacer()
                Button("Quit Claude Meter", action: onQuit)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
    }

    /// Snapshot the views should render — debug override if enabled, real
    /// store data otherwise.
    private var displaySnapshot: UsageSnapshot? {
        settings.debug.enabled ? settings.debug.syntheticSnapshot() : store.snapshot
    }

    private func displayProjection(for window: TrackedWindow) -> Projection? {
        if settings.debug.enabled {
            if let synthetic = settings.debug.syntheticProjection(for: window) {
                return synthetic
            }
            // Debug "No projection" outcome — fall back to a snapshot-
            // derived pace ratio so the gauges still have something to
            // render. The "No projection" option survives from the old
            // bars UI that relied on an explicit suppression state; the
            // gauges don't have an equivalent "off" mode.
            return snapshotProjection(for: window, snapshot: displaySnapshot)
        }
        return store.projection(for: window)
    }

    private func snapshotProjection(for window: TrackedWindow, snapshot: UsageSnapshot?) -> Projection? {
        guard let snapshot else { return nil }
        switch window {
        case .fiveHour:
            guard let w = snapshot.fiveHour else { return nil }
            return Projector.project(window: w, windowDuration: UsageStore.fiveHourDuration)
        case .sevenDay:
            guard let w = snapshot.sevenDay else { return nil }
            return Projector.project(window: w, windowDuration: UsageStore.sevenDayDuration)
        }
    }

    // MARK: - Pacing status sentence

    /// Single status line shown beneath both gauges. Picks the message
    /// based on which zone each pacing ratio falls into:
    /// - both `< 85%` → under-utilized advice
    /// - any `85–110%` → on-target affirmation
    /// - any `> 110%` → burnout warning, naming the offending window
    ///   (Weekly takes precedence when both are over).
    private var pacingStatus: PacingStatusMessage? {
        let session = displayProjection(for: .fiveHour)
        let weekly = displayProjection(for: .sevenDay)
        let sessionZone = pacingZone(session)
        let weeklyZone = pacingZone(weekly)

        if weeklyZone == .over, let p = weekly {
            return .burnout(label: "Weekly", deadTime: deadTime(of: p))
        }
        if sessionZone == .over, let p = session {
            return .burnout(label: "Session", deadTime: deadTime(of: p))
        }
        if sessionZone == .target || weeklyZone == .target {
            return .onTarget
        }
        if sessionZone == .under && weeklyZone == .under {
            return .underUtilized
        }
        return nil
    }

    private enum PacingZone { case under, target, over, unknown }

    private func pacingZone(_ p: Projection?) -> PacingZone {
        guard let p else { return .unknown }
        if p.paceRatio < 0.85 { return .under }
        if p.paceRatio <= 1.10 { return .target }
        return .over
    }

    private func deadTime(of projection: Projection) -> TimeInterval {
        if case .overPace(let dt) = projection.outcome { return dt }
        return 0
    }

    enum PacingStatusMessage {
        case underUtilized
        case onTarget
        case burnout(label: String, deadTime: TimeInterval)

        var text: String {
            switch self {
            case .underUtilized:
                return "Under utilized. Use more tokens."
            case .onTarget:
                return "On target. Maintain token spend."
            case .burnout(let label, let dt):
                return "\(label) burnout projected \(DurationFormatter.coarse(dt)) early. Reduce token spend."
            }
        }

        var color: Color {
            switch self {
            case .underUtilized: return .secondary
            case .onTarget: return .usageGreen
            case .burnout: return .criticalRed
            }
        }
    }

    private func footerText(now: Date) -> String {
        guard let last = displayLastRefresh else {
            return store.lastError == nil ? "Loading…" : "Never refreshed"
        }
        let elapsed = max(0, now.timeIntervalSince(last))
        if elapsed < 2 { return "Updated just now" }
        if elapsed < 60 { return "Updated \(Int(elapsed))s ago" }
        return "Updated \(DurationFormatter.compact(elapsed)) ago"
    }

    private var displayLastRefresh: Date? {
        if settings.debug.enabled {
            return Date().addingTimeInterval(-settings.debug.minutesSinceUpdate * 60)
        }
        return store.lastRefresh
    }

    /// Whether to render the "API currently unavailable" status line. True
    /// when the most recent poll failed with an API error (rate limit,
    /// network, server, etc.) and we still have a cached snapshot to show,
    /// or when debug is forcing the unavailable state.
    private var displayApiUnavailable: Bool {
        if settings.debug.enabled { return settings.debug.apiUnavailable }
        guard case .api = store.lastError else { return false }
        return displaySnapshot != nil
    }

    /// Inline, actionable error shown above the divider. Reserved for
    /// sign-in problems and a few API errors that *require* user action
    /// (unauthorized, scope mismatch, etc.). Generic API failures
    /// (rate limit, network, 5xx) surface in the footer's "API currently
    /// unavailable" line instead, since the cached snapshot is still
    /// showing useful data and the user has nothing to do but wait.
    private var signInMessage: String? {
        guard let err = store.lastError else { return nil }
        switch err {
        case .tokenRead(let tokenErr):
            switch tokenErr {
            case .keychainItemNotFound, .configFileMissing, .configKeyMissing:
                return "Open Claude desktop and sign in to enable Claude Meter."
            case .keychainAccessDenied:
                return "Allow Keychain access in System Settings → Privacy & Security."
            case .unsupportedScheme, .base64DecodeFailed, .plaintextNotJSON:
                return "Claude desktop changed its storage format. Update Claude Meter."
            case .decryptionFailed:
                return "Couldn't decrypt Claude desktop's sign-in. Update Claude Meter."
            case .noUsableToken:
                return "Open Claude desktop to refresh your sign-in."
            case .configReadFailed:
                return "Couldn't read Claude desktop's config file."
            case .keychainOther:
                return "Couldn't read Keychain. Try again."
            }
        case .api(let apiErr):
            switch apiErr {
            case .unauthorized:
                return "Open Claude desktop to refresh your sign-in."
            case .forbidden:
                return "Authorization scope changed — Claude Meter may need an update."
            case .notFound, .decoding:
                return "Claude Meter needs an update."
            case .rateLimited, .server, .network, .invalidResponse, .unexpected:
                return nil
            }
        }
    }
}

#Preview("Signed in — fresh data") {
    let store = UsageStore()
    store.updateSnapshot(UsageSnapshot(
        fiveHour: UsageWindow(utilization: 14.0,
                              resetsAt: Date().addingTimeInterval(3 * 3600)),
        sevenDay: UsageWindow(utilization: 65.0,
                              resetsAt: Date().addingTimeInterval(2 * 86400))
    ))
    return UsagePopover(store: store, settings: AppSettings(), onRefresh: {}, onQuit: {})
}

#Preview("Loading") {
    let store = UsageStore()
    return UsagePopover(store: store, settings: AppSettings(), onRefresh: {}, onQuit: {})
}

#Preview("Network error with stale snapshot") {
    let store = UsageStore()
    store.updateSnapshot(UsageSnapshot(
        fiveHour: UsageWindow(utilization: 14.0,
                              resetsAt: Date().addingTimeInterval(3 * 3600)),
        sevenDay: UsageWindow(utilization: 65.0,
                              resetsAt: Date().addingTimeInterval(2 * 86400))
    ), at: Date().addingTimeInterval(-15 * 60))
    store.recordError(.api(.network(underlying: URLError(.notConnectedToInternet))))
    return UsagePopover(store: store, settings: AppSettings(), onRefresh: {}, onQuit: {})
}
