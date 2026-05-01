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

            VStack(alignment: .leading, spacing: 6) {
                utilizationRow(label: "Session Token Utilization", window: displaySnapshot?.fiveHour)
                utilizationRow(label: "Weekly Token Utilization", window: displaySnapshot?.sevenDay)
            }

            if let message = signInMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(footerText(now: context.date))
                        if displayApiUnavailable {
                            Text("API currently unavailable")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func utilizationRow(label: String, window: UsageWindow?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(utilizationText(for: window))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(utilizationColor(for: window))
        }
    }

    private func utilizationText(for window: UsageWindow?) -> String {
        guard let w = window else { return "—" }
        return "\(Int(w.utilization.rounded()))%"
    }

    private func utilizationColor(for window: UsageWindow?) -> Color {
        guard let w = window else { return .secondary }
        if w.utilization > 100 { return .criticalRed }
        if w.utilization >= 85 { return .usageYellow }
        return .primary
    }

    /// Snapshot the views should render — debug override if enabled, real
    /// store data otherwise.
    private var displaySnapshot: UsageSnapshot? {
        settings.debug.enabled ? settings.debug.syntheticSnapshot() : store.snapshot
    }

    private func displayProjection(for window: TrackedWindow) -> Projection? {
        settings.debug.enabled
            ? settings.debug.syntheticProjection(for: window)
            : store.projection(for: window)
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
