import SwiftUI

/// The click-to-reveal panel shown when the user is signed in. Observes
/// `UsageStore` directly. The owner of the store is responsible for
/// passing in callbacks for refresh / quit / sign-out actions.
struct UsagePopover: View {
    let store: UsageStore
    let launchAtLogin: LaunchAtLogin
    let onRefresh: () -> Void
    let onSignOut: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageBar(title: "5 hours", window: store.snapshot?.fiveHour)
            UsageBar(title: "7 days", window: store.snapshot?.sevenDay)

            if let message = errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            HStack {
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)

            HStack {
                Button("Sign Out", action: onSignOut)
                    .buttonStyle(.borderless)
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
        case .unauthorized:
            return "Authentication failed — please sign in again."
        case .forbidden:
            return "Re-authorization required."
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

#Preview("Signed in — fresh data") {
    let store = UsageStore()
    store.updateSnapshot(UsageSnapshot(
        fiveHour: UsageWindow(utilization: 14.0,
                              resetsAt: Date().addingTimeInterval(3 * 3600)),
        sevenDay: UsageWindow(utilization: 65.0,
                              resetsAt: Date().addingTimeInterval(2 * 86400))
    ))
    return UsagePopover(store: store, launchAtLogin: LaunchAtLogin(), onRefresh: {}, onSignOut: {}, onQuit: {})
}

#Preview("Loading") {
    let store = UsageStore()
    return UsagePopover(store: store, launchAtLogin: LaunchAtLogin(), onRefresh: {}, onSignOut: {}, onQuit: {})
}

#Preview("Network error with stale snapshot") {
    let store = UsageStore()
    store.updateSnapshot(UsageSnapshot(
        fiveHour: UsageWindow(utilization: 14.0,
                              resetsAt: Date().addingTimeInterval(3 * 3600)),
        sevenDay: UsageWindow(utilization: 65.0,
                              resetsAt: Date().addingTimeInterval(2 * 86400))
    ), at: Date().addingTimeInterval(-15 * 60))
    store.recordError(.network(underlying: URLError(.notConnectedToInternet)))
    return UsagePopover(store: store, launchAtLogin: LaunchAtLogin(), onRefresh: {}, onSignOut: {}, onQuit: {})
}
