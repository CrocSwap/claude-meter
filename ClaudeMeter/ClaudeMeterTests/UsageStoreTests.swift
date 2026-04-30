import Foundation
import Testing
@testable import ClaudeMeter

@MainActor
@Suite("UsageStore")
struct UsageStoreTests {

    @Test("Initial state is empty")
    func initialState() {
        let store = UsageStore()
        #expect(store.snapshot == nil)
        #expect(store.lastRefresh == nil)
        #expect(store.lastError == nil)
    }

    @Test("updateSnapshot sets snapshot + timestamp and clears error")
    func updateClearsError() {
        let store = UsageStore()
        store.recordError(.api(.unauthorized))
        #expect(store.lastError != nil)

        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 14.0, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 65.0, resetsAt: nil)
        )
        let date = Date(timeIntervalSince1970: 1_777_577_933)
        store.updateSnapshot(snapshot, at: date)

        #expect(store.snapshot == snapshot)
        #expect(store.lastRefresh == date)
        #expect(store.lastError == nil)
    }

    @Test("recordError preserves the last good snapshot")
    func errorPreservesSnapshot() {
        let store = UsageStore()
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 14.0, resetsAt: nil),
            sevenDay: nil
        )
        store.updateSnapshot(snapshot)

        store.recordError(.api(.unauthorized))

        #expect(store.snapshot == snapshot, "snapshot should survive a recorded error")
        #expect(store.lastError != nil)
    }

    @Test("clear wipes everything")
    func clearWipes() {
        let store = UsageStore()
        store.updateSnapshot(UsageSnapshot(fiveHour: nil, sevenDay: nil))
        store.recordError(.api(.unauthorized))
        store.clear()
        #expect(store.snapshot == nil)
        #expect(store.lastRefresh == nil)
        #expect(store.lastError == nil)
    }
}
