import SwiftUI

/// Standard macOS settings sheet, opened from the popover gear (and via ⌘,).
/// Backed by the `Settings` scene in `ClaudeMeterApp`. All persistence goes
/// through `AppSettings` / `LaunchAtLogin` — this view only renders bindings.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Display", selection: $settings.displayMode) {
                    Text("Vessel").tag(DisplayMode.vessel)
                    Text("Pacing").tag(DisplayMode.pacing)
                    Text("Numeric").tag(DisplayMode.numeric)
                }
                .pickerStyle(.segmented)

                Picker("Tracked window", selection: $settings.trackedWindow) {
                    Text("5 hours").tag(TrackedWindow.fiveHour)
                    Text("7 days").tag(TrackedWindow.sevenDay)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Show under-pace info in popover", isOn: $settings.showUnderPaceAnnotation)
            } header: {
                Text("Annotations")
            } footer: {
                Text("Shows projected unused capacity when you're tracking below pace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}

#Preview {
    SettingsView(settings: AppSettings(), launchAtLogin: LaunchAtLogin())
}
