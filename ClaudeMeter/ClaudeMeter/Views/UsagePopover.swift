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
            if settings.debug.enabled && !settings.debug.hideBanner {
                Text("DEBUG MODE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.usageYellow)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            UsageBar(title: "Session", window: displaySnapshot?.fiveHour)
            UsageBar(title: "Weekly", window: displaySnapshot?.sevenDay)

            Divider()

            sectionTitle("PACING")
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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let status = pacingStatus(now: context.date) {
                        Text(status.text)
                            .font(.footnote)
                            .foregroundStyle(status.color)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Menubar")
                    Picker("", selection: trackedWindowBinding) {
                        Text("Session").tag(TrackedWindow.fiveHour)
                        Text("Weekly").tag(TrackedWindow.sevenDay)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
                Toggle("Show Usage in Menubar", isOn: showUsageBinding)
                    .toggleStyle(.checkbox)
                    .disabled(onlyUsageChecked)
                Toggle("Show Pacing in Menubar", isOn: showPacingBinding)
                    .toggleStyle(.checkbox)
                    .disabled(onlyPacingChecked)
                Toggle("Show % in Menubar", isOn: showPercentBinding)
                    .toggleStyle(.checkbox)
            }
            .font(.subheadline)

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

    /// Small uppercase header for the popover sections — same caption2/
    /// semibold weight as the per-row "SESSION"/"WEEKLY" labels so the
    /// hierarchy reads as "section header → row label."
    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Menu-bar visibility checkboxes

    /// True when only the usage box is checked — disables it so the user
    /// can't uncheck the only remaining option.
    private var onlyUsageChecked: Bool {
        settings.showUsageInMenuBar && !settings.showPacingInMenuBar
    }

    private var onlyPacingChecked: Bool {
        !settings.showUsageInMenuBar && settings.showPacingInMenuBar
    }

    /// Bindings that defensively refuse to set both flags to false. The
    /// `.disabled(...)` modifier already prevents the click in the UI, but
    /// the guard keeps the invariant intact if anything else tries to
    /// flip the state.
    private var showUsageBinding: Binding<Bool> {
        Binding(
            get: { settings.showUsageInMenuBar },
            set: { newValue in
                if !newValue && !settings.showPacingInMenuBar { return }
                settings.showUsageInMenuBar = newValue
            }
        )
    }

    private var showPacingBinding: Binding<Bool> {
        Binding(
            get: { settings.showPacingInMenuBar },
            set: { newValue in
                if !newValue && !settings.showUsageInMenuBar { return }
                settings.showPacingInMenuBar = newValue
            }
        )
    }

    /// Independent of the gauge-visibility toggles — this one has no
    /// invariant to defend, it just maps straight through.
    private var showPercentBinding: Binding<Bool> {
        Binding(
            get: { settings.showPercentInMenuBar },
            set: { settings.showPercentInMenuBar = $0 }
        )
    }

    private var trackedWindowBinding: Binding<TrackedWindow> {
        Binding(
            get: { settings.trackedWindow },
            set: { settings.trackedWindow = $0 }
        )
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
    ///
    /// `now` is threaded through so the burnout line's "limits hitting in
    /// X" stays live as time passes.
    private func pacingStatus(now: Date) -> PacingStatusMessage? {
        let session = displayProjection(for: .fiveHour)
        let weekly = displayProjection(for: .sevenDay)
        let sessionZone = pacingZone(session)
        let weeklyZone = pacingZone(weekly)

        if weeklyZone == .over, let p = weekly {
            return makeBurnout(label: "Weekly",
                               projection: p,
                               window: displaySnapshot?.sevenDay,
                               now: now)
        }
        if sessionZone == .over, let p = session {
            return makeBurnout(label: "Session",
                               projection: p,
                               window: displaySnapshot?.fiveHour,
                               now: now)
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

    /// Build a `.burnout` message. `timeUntilLockout = secondsUntilReset
    /// − deadTime`; we get `secondsUntilReset` from the window (the only
    /// place it's stored) rather than threading it through `Projection`.
    private func makeBurnout(
        label: String,
        projection: Projection,
        window: UsageWindow?,
        now: Date
    ) -> PacingStatusMessage {
        let dt: TimeInterval
        if case .overPace(let d) = projection.outcome { dt = d } else { dt = 0 }
        let secondsUntilReset: TimeInterval
        if let resets = window?.resetsAt {
            secondsUntilReset = max(0, resets.timeIntervalSince(now))
        } else {
            secondsUntilReset = 0
        }
        let timeUntilLockout = max(0, secondsUntilReset - dt)
        return .burnout(label: label, timeUntilLockout: timeUntilLockout, deadTime: dt)
    }

    enum PacingStatusMessage {
        case underUtilized
        case onTarget
        case burnout(label: String, timeUntilLockout: TimeInterval, deadTime: TimeInterval)

        var text: String {
            switch self {
            case .underUtilized:
                return "Under utilized. Use more tokens."
            case .onTarget:
                return "On target. Maintain token spend."
            case .burnout(let label, let lockoutIn, let dead):
                let lock = DurationFormatter.coarse(lockoutIn)
                let deadStr = DurationFormatter.coarse(dead)
                return "\(label) limits hitting in \(lock).\nWill lose \(deadStr) of subscription access"
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
