import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var store: UsageStore
    @State private var launchAtLogin: LaunchAtLogin
    @State private var settings: AppSettings
    @State private var poller: UsagePoller

    init() {
        let store = UsageStore()
        let poller = UsagePoller(
            store: store,
            tokenSource: { try TokenReader.currentToken() }
        )
        _store = State(initialValue: store)
        _launchAtLogin = State(initialValue: LaunchAtLogin())
        _settings = State(initialValue: AppSettings())
        _poller = State(initialValue: poller)
        Task { await poller.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(
                store: store,
                settings: settings,
                onRefresh: { Task { await poller.refreshNow() } },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .onAppear { Task { await poller.setPopoverOpen(true) } }
            .onDisappear { Task { await poller.setPopoverOpen(false) } }
        } label: {
            MenuBarLabel(store: store, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, launchAtLogin: launchAtLogin)
        }
    }
}
