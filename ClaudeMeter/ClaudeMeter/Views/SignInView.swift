import SwiftUI

/// Shown in the popover when no OAuth session exists. The only path forward
/// is the sign-in button, which kicks off `OAuthClient.signIn()`. Until
/// that lands (task #5, blocked on #9), the button calls a placeholder
/// closure that should be wired up by the app once OAuthClient exists.
struct SignInView: View {
    let onSignIn: () -> Void
    let onQuit: () -> Void
    var isWorking: Bool = false
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3)
                Text("Claude Meter")
                    .font(.headline)
            }
            Text("Sign in to track your 5-hour and 7-day usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: onSignIn) {
                HStack {
                    if isWorking { ProgressView().scaleEffect(0.7) }
                    Text(isWorking ? "Signing in…" : "Sign in with Anthropic")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            Divider()

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

#Preview("Idle") {
    SignInView(onSignIn: {}, onQuit: {})
}

#Preview("Working") {
    SignInView(onSignIn: {}, onQuit: {}, isWorking: true)
}

#Preview("Error") {
    SignInView(onSignIn: {}, onQuit: {}, errorMessage: "Sign-in cancelled.")
}
