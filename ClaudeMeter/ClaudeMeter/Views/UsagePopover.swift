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
                title: "5 hours",
                window: store.snapshot?.fiveHour,
                projection: store.projection(for: .fiveHour),
                showUnderPaceAnnotation: settings.showUnderPaceAnnotation
            )
            UsageBar(
                title: "7 days",
                window: store.snapshot?.sevenDay,
                projection: store.projection(for: .sevenDay),
                showUnderPaceAnnotation: settings.showUnderPaceAnnotation
            )

            if let message = errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            HStack(spacing: 8) {
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private var footerText: String {
        guard let last = store.lastRefresh else {
            return store.lastError == nil ? "Loading…" : "Never refreshed"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: last, relativeTo: Date()))"
    }

    private var errorMessage: String? {
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
            case .notFound:
                return "Claude Meter needs an update."
            case .server(let s):
                return "Anthropic server error (HTTP \(s)). Retrying…"
            case .network:
                return "Offline. Showing last known values."
            case .decoding:
                return "Couldn't parse the response. Claude Meter needs an update."
            case .invalidResponse, .unexpected:
                return "Unexpected response. Will retry."
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
