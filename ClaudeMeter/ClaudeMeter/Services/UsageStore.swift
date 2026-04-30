import Foundation
import Observation

/// Single source of truth for usage state. Views observe directly via
/// the Observation macros; UsagePoller is the sole writer.
///
/// Snapshot and error are kept independently: a network failure does not
/// erase the last good snapshot — the popover can show stale data plus a
/// "haven't refreshed since X" hint.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastRefresh: Date?
    private(set) var lastError: AnthropicAPI.APIError?

    func updateSnapshot(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        self.snapshot = snapshot
        self.lastRefresh = date
        self.lastError = nil
    }

    func recordError(_ error: AnthropicAPI.APIError) {
        self.lastError = error
    }

    /// Used when the user signs out: forget all cached data.
    func clear() {
        self.snapshot = nil
        self.lastRefresh = nil
        self.lastError = nil
    }
}
