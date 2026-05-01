import SwiftUI
import AppKit

/// Standard macOS settings sheet, opened from the popover gear (and via ⌘,).
/// Backed by the `Settings` scene in `ClaudeMeterApp`. All persistence goes
/// through `AppSettings` / `LaunchAtLogin` — this view only renders bindings.
///
/// `LSUIElement = true` keeps the app out of the Dock, but it also means the
/// settings window won't auto-front when opened via `SettingsLink`. The
/// `onAppear` hop pulls the app forward and brings the window to the top so
/// it doesn't hide behind whatever the user was looking at.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var debug: DebugSettings
    let launchAtLogin: LaunchAtLogin
    @State private var debugVisible: Bool = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
            }

            if debugVisible || debug.enabled {
                debugSection
            }
        }
        .formStyle(.grouped)
        // Keep selection chrome (toggle blue, picker accent, etc.) vibrant
        // even when the settings window loses focus to the menu-bar popover.
        // Default macOS behavior desaturates these to gray when the window
        // is non-key, which makes "On" toggles look identical to "Off."
        .environment(\.controlActiveState, .key)
        .frame(
            width: debugVisible || debug.enabled ? 580 : 480,
            height: debugVisible || debug.enabled ? 880 : 560
        )
        .background(
            // Invisible button registers ⌥⌘⇧D as the reveal shortcut.
            Button("") { debugVisible.toggle() }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.title.contains("Settings") {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        Section {
            Toggle("Override API values", isOn: $debug.enabled)
                .toggleStyle(.switch)

            if debug.enabled {
                debugWindowControls(
                    title: "5-hour window",
                    util: $debug.fiveHourUtil,
                    minutesToReset: $debug.fiveHourMinutesToReset,
                    outcome: $debug.fiveHourOutcome,
                    overPaceHours: $debug.fiveHourOverPaceHours,
                    unusedFraction: $debug.fiveHourUnusedFraction
                )
                Divider()
                debugWindowControls(
                    title: "7-day window",
                    util: $debug.sevenDayUtil,
                    minutesToReset: $debug.sevenDayMinutesToReset,
                    outcome: $debug.sevenDayOutcome,
                    overPaceHours: $debug.sevenDayOverPaceHours,
                    unusedFraction: $debug.sevenDayUnusedFraction
                )
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status").font(.subheadline.weight(.semibold))

                    Toggle("Simulate API unavailable", isOn: $debug.apiUnavailable)
                        .toggleStyle(.switch)

                    HStack {
                        Text("Last updated")
                            .frame(width: 110, alignment: .leading)
                        TextField("", value: $debug.minutesSinceUpdate, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("minutes ago")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Hidden developer mode — overrides what the menu bar and popover display so you can preview every visual state without burning real quota. ⌥⌘⇧D toggles visibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func debugWindowControls(
        title: String,
        util: Binding<Double>,
        minutesToReset: Binding<Double>,
        outcome: Binding<DebugOutcomeKind>,
        overPaceHours: Binding<Double>,
        unusedFraction: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))

            HStack {
                Text("Utilization")
                    .frame(width: 110, alignment: .leading)
                Slider(value: util, in: 0...100)
                Text("\(Int(util.wrappedValue.rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            HStack {
                Text("Resets in")
                    .frame(width: 110, alignment: .leading)
                TextField("", value: minutesToReset, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("minutes")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text("Projection")
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: outcome) {
                    ForEach(DebugOutcomeKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if outcome.wrappedValue == .overPace {
                HStack {
                    Text("Dead time")
                        .frame(width: 110, alignment: .leading)
                    TextField("", value: overPaceHours, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("hours")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if outcome.wrappedValue == .underPace {
                HStack {
                    Text("Unused at reset")
                        .frame(width: 110, alignment: .leading)
                    Slider(value: unusedFraction, in: 0...1)
                    Text("\(Int((unusedFraction.wrappedValue * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let s = AppSettings()
    return SettingsView(settings: s, debug: s.debug, launchAtLogin: LaunchAtLogin())
}
