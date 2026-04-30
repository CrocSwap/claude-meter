import SwiftUI

@main
struct ClaudeMeterApp: App {
    var body: some Scene {
        MenuBarExtra("Claude Meter", systemImage: "battery.100") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Meter")
                    .font(.headline)
                Text("Not yet implemented")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit Claude Meter") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(12)
            .frame(width: 240)
        }
        .menuBarExtraStyle(.window)
    }
}
