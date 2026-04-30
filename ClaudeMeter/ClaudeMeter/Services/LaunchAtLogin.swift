import Foundation
import ServiceManagement
import os

/// Wraps `SMAppService.mainApp` with an Observable surface so the popover
/// toggle can read/write the value as a binding. Errors are logged and
/// surfaced via `lastError` rather than thrown — toggling launch-at-login
/// shouldn't be able to crash the app.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "dev.claudemeter", category: "launch-at-login")

    init() {
        refreshFromSystem()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            logger.error("SMAppService toggle failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
        refreshFromSystem()
    }

    private func refreshFromSystem() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
