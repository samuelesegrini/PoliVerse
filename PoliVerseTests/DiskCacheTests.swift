import Foundation
import Testing
@testable import PoliVerse

/// The cache that lets the app open with content instead of a spinner.
///
/// Nothing here calls `DiskCache.clear()`: it removes the whole folder, and
/// other tests build services that write to it. Each test uses a name of its
/// own instead, which is also how the app uses it.
@Suite("Cache su disco")
struct DiskCacheTests {
    private struct Payload: Codable, Equatable, Sendable {
        var courses: [String]
        var count: Int
    }

    private func name() -> String { "test-\(UUID().uuidString)" }

    @Test("Quello che si salva si rilegge uguale")
    func roundTrip() throws {
        let key = name()
        let payload = Payload(courses: ["Basi di Dati", "Reti Logiche"], count: 2)
        DiskCache.save(payload, as: key)

        let entry = try #require(DiskCache.load(Payload.self, as: key))
        #expect(entry.value == payload)
    }

    /// The write stamps the moment, so a caller can tell a cache written a
    /// minute ago from one written last term.
    @Test("Ogni voce porta quando è stata scritta")
    func stampsTheMoment() throws {
        let key = name()
        let before = Date.now
        DiskCache.save(Payload(courses: [], count: 0), as: key)
        let entry = try #require(DiskCache.load(Payload.self, as: key))

        #expect(entry.storedAt >= before)
        #expect(entry.storedAt <= Date.now)
    }

    @Test("La freschezza si misura sulla finestra chiesta")
    func freshness() {
        let fresh = DiskCache.Entry(value: 1, storedAt: .now)
        #expect(fresh.isFresh(within: 60))

        let old = DiskCache.Entry(value: 1, storedAt: Date.now.addingTimeInterval(-3600))
        #expect(!old.isFresh(within: 60))
        #expect(old.isFresh(within: 7200))
    }

    /// The first launch, and every name the app has not written yet: nil, not
    /// an empty value that would read as "loaded and empty".
    @Test("Un nome mai scritto torna nil")
    func missing() {
        #expect(DiskCache.load(Payload.self, as: name()) == nil)
    }

    /// A payload that no longer decodes into the type asked for — the shape
    /// changed between releases — is a miss, not a crash.
    @Test("Una voce che non corrisponde più al tipo è una mancanza")
    func typeMismatch() {
        let key = name()
        DiskCache.save(Payload(courses: ["Analisi"], count: 1), as: key)
        #expect(DiskCache.load([String].self, as: key) == nil)
    }

    @Test("Riscrivere un nome sostituisce quello che c’era")
    func overwrite() throws {
        let key = name()
        DiskCache.save(Payload(courses: ["prima"], count: 1), as: key)
        DiskCache.save(Payload(courses: ["dopo"], count: 1), as: key)

        let entry = try #require(DiskCache.load(Payload.self, as: key))
        #expect(entry.value.courses == ["dopo"])
    }

    /// Impostazioni shows the size; it has to count what was just written.
    @Test("La dimensione su disco cresce con quello che si scrive")
    func size() {
        let before = DiskCache.sizeInBytes()
        DiskCache.save(Payload(courses: Array(repeating: "Ingegneria del Software", count: 200), count: 200), as: name())
        #expect(DiskCache.sizeInBytes() > before)
    }
}
