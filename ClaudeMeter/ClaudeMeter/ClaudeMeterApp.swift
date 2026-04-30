import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var store = UsageStore()
    @State private var launchAtLogin = LaunchAtLogin()
    // Placeholder — replaced with `OAuthClient.isSignedIn` once #5 lands.
    @State private var isSignedIn: Bool = false

    var body: some Scene {
        MenuBarExtra {
            if isSignedIn {
                UsagePopover(
                    store: store,
                    launchAtLogin: launchAtLogin,
                    onRefresh: refreshNow,
                    onSignOut: signOut,
                    onQuit: quit
                )
            } else {
                SignInView(
                    onSignIn: signIn,
                    onQuit: quit
                )
            }
        } label: {
            MenuBarLabel(
                snapshot: store.snapshot,
                hasError: store.lastError != nil
            )
        }
        .menuBarExtraStyle(.window)
    }

    private func signIn() {
        // Stub: kicked off in task #5 once OAuthClient exists.
    }

    private func signOut() {
        store.clear()
        isSignedIn = false
    }

    private func refreshNow() {
        // Stub: forwarded to UsagePoller.refreshNow() once wired.
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
