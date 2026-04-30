import Foundation
import Testing
@testable import ClaudeMeter

@Suite("UsagePoller")
struct UsagePollerTests {

    @Test("Base interval used when no failures (popover closed)")
    func baseIntervalNoFailuresClosed() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            tokenSource: { "fake" },
            normalInterval: 60,
            activeInterval: 15,
            backoffCeiling: 300
        )
        let interval = await poller.nextInterval()
        #expect(interval == 60)
    }

    @Test("Active (faster) interval used when popover open")
    func activeIntervalNoFailuresOpen() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            tokenSource: { "fake" },
            normalInterval: 60,
            activeInterval: 15,
            backoffCeiling: 300
        )
        await poller.setPopoverOpen(true)
        let interval = await poller.nextInterval()
        #expect(interval == 15)
    }

    @Test("Backoff doubles on each failure, capped at ceiling")
    func backoffDoublesAndCaps() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            tokenSource: { throw FakeError.boom },
            normalInterval: 60,
            activeInterval: 15,
            backoffCeiling: 300
        )

        // 1 failure: 60 * 2^0 = 60
        await poller.refreshNow()
        var iv = await poller.nextInterval()
        #expect(iv == 60)

        // 2 failures: 60 * 2^1 = 120
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 120)

        // 3 failures: 60 * 2^2 = 240
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 240)

        // 4 failures: 60 * 2^3 = 480 → capped at 300
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 300)

        // 10 failures: still capped
        for _ in 0..<6 { await poller.refreshNow() }
        iv = await poller.nextInterval()
        #expect(iv == 300)
    }

    @Test("Recorded error survives in store after failed pollOnce")
    func failurePropagatesToStore() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            tokenSource: { throw FakeError.boom },
            normalInterval: 60,
            activeInterval: 15
        )
        await poller.refreshNow()
        let hasError = await MainActor.run { store.lastError != nil }
        #expect(hasError)
    }
}

private enum FakeError: Error {
    case boom
}
