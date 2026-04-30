import Foundation

/// Drives `UsageStore` with periodic API calls. Owns its task lifecycle.
///
/// Polling cadence follows AGENTS.md: 60s by default, 15s while the popover
/// is open. On error, exponential backoff with a 5-minute ceiling.
///
/// The `tokenSource` closure decouples this layer from `OAuthClient` —
/// at integration time it'll be `oauthClient.currentAccessToken`. For tests
/// it can be any `() async throws -> String`.
actor UsagePoller {
    typealias TokenSource = @Sendable () async throws -> String

    private let store: UsageStore
    private let tokenSource: TokenSource
    private let normalInterval: TimeInterval
    private let activeInterval: TimeInterval
    private let backoffCeiling: TimeInterval
    private let session: URLSession

    private var task: Task<Void, Never>?
    private var isPopoverOpen: Bool = false
    private var consecutiveFailures: Int = 0

    init(
        store: UsageStore,
        tokenSource: @escaping TokenSource,
        normalInterval: TimeInterval = 60,
        activeInterval: TimeInterval = 15,
        backoffCeiling: TimeInterval = 300,
        session: URLSession = .shared
    ) {
        self.store = store
        self.tokenSource = tokenSource
        self.normalInterval = normalInterval
        self.activeInterval = activeInterval
        self.backoffCeiling = backoffCeiling
        self.session = session
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func setPopoverOpen(_ open: Bool) {
        self.isPopoverOpen = open
    }

    /// Force an out-of-band poll (e.g. user clicks "Refresh"). Resets the
    /// next-tick timer is *not* the caller's job — the running loop's sleep
    /// is unaffected, but the snapshot updates immediately.
    func refreshNow() async {
        await pollOnce()
    }

    // Exposed for tests; computes the next sleep interval given current state.
    func nextInterval() -> TimeInterval {
        let base = isPopoverOpen ? activeInterval : normalInterval
        guard consecutiveFailures > 0 else { return base }
        let backoff = base * pow(2.0, Double(consecutiveFailures - 1))
        return min(backoff, backoffCeiling)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            let seconds = nextInterval()
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    private func pollOnce() async {
        let token: String
        do {
            token = try await tokenSource()
        } catch let err as TokenReader.ReadError {
            await store.recordError(.tokenRead(err))
            consecutiveFailures += 1
            return
        } catch {
            await store.recordError(.api(.network(underlying: error)))
            consecutiveFailures += 1
            return
        }

        do {
            let snapshot = try await AnthropicAPI.fetchUsage(token: token, session: session)
            await store.updateSnapshot(snapshot)
            consecutiveFailures = 0
        } catch let err as AnthropicAPI.APIError {
            await store.recordError(.api(err))
            consecutiveFailures += 1
        } catch {
            await store.recordError(.api(.network(underlying: error)))
            consecutiveFailures += 1
        }
    }
}
