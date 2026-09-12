import Foundation
import Testing
@testable import PoliVerse

/// The bug this type exists to make impossible.
///
/// The first offline attempt restored from disk in each service's `init()`.
/// Those run inside `PoliVerseApp.init()`, and `Session.restore()` runs later,
/// from `RootView.task` — so at construction time the matricola was still nil,
/// every restore asked for account `nil`, and **nothing was ever restored**.
/// The feature looked finished and did nothing.
///
/// A slot restores lazily, keyed by the account it restored for, so it cannot
/// run before the account is known — and re-runs when the account changes,
/// which is a single tap away now that careers can be switched.
@Suite("Cached slot")
struct CachedSlotTests {
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("Nothing is restored while the account is unknown")
    func waitsForAccount() {
        let store = store()
        store.save(Payload(value: "cached"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        // This is the moment the old code ran, and got nothing.
        #expect(slot.restore(for: nil) == nil)
        #expect(slot.age == nil)
    }

    /// The fix: once the account arrives, the restore happens.
    @Test("The value is restored once the account is known")
    func restoresLater() {
        let store = store()
        store.save(Payload(value: "cached"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        #expect(slot.restore(for: nil) == nil)
        #expect(slot.restore(for: "111")?.value == "cached")
        #expect(slot.age != nil)
    }

    @Test("Restoring twice for the same account reads the disk once")
    func restoresOnce() {
        let store = store()
        store.save(Payload(value: "cached"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        #expect(slot.restore(for: "111")?.value == "cached")
        // A second call must not re-read: the in-memory value may since have
        // been updated by a fetch, and re-reading would undo it.
        #expect(slot.restore(for: "111") == nil)
    }

    /// Switching career must show that career's data, not the previous one's.
    @Test("Changing account restores again")
    func accountChange() {
        let store = store()
        store.save(Payload(value: "triennale"), as: "x", account: "986617")
        store.save(Payload(value: "magistrale"), as: "x", account: "332218")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        #expect(slot.restore(for: "986617")?.value == "triennale")
        #expect(slot.restore(for: "332218")?.value == "magistrale")
    }

    @Test("Saving records the account so no restore undoes it")
    func saveMarksRestored() {
        let store = store()
        store.save(Payload(value: "old"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        slot.save(Payload(value: "fresh"), for: "111")
        // A restore now would overwrite fresher data with what is on disk.
        #expect(slot.restore(for: "111") == nil)
        #expect(slot.age == 0)
    }

    @Test("Sample data is not written")
    func refusesMock() {
        let store = store()
        var slot = CachedSlot<Payload>(name: "x", store: store)
        slot.save(Payload(value: "mock"), for: nil)
        #expect(store.load(Payload.self, as: "x", account: nil) == nil)
    }
}
