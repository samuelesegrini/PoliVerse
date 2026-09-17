import Foundation
import Testing
@testable import PoliVerse

/// The scrapers compile the same handful of patterns thousands of times while
/// reading one Manifesti page. The cache is the fix; these pin that it hands
/// back the same compiled expression, that it does not hide a bad pattern,
/// and that it stays correct when several threads ask at once.
@Suite("Cache delle espressioni regolari")
struct RegexCacheTests {
    /// A pattern per test, so tests running in parallel never observe each
    /// other's entries.
    private func pattern(_ suffix: String = "") -> String {
        "test-\(UUID().uuidString)\(suffix)"
    }

    @Test("Lo stesso pattern torna la stessa espressione compilata")
    func reusesTheSameInstance() throws {
        let source = pattern()
        let first = try #require(RegexCache.regex(source))
        let second = try #require(RegexCache.regex(source))
        #expect(first === second)
    }

    /// Options are part of the key: a case-insensitive expression is not the
    /// same object as a case-sensitive one built from the same pattern.
    @Test("Opzioni diverse sono voci diverse")
    func optionsArePartOfTheKey() throws {
        let source = pattern()
        let plain = try #require(RegexCache.regex(source))
        let insensitive = try #require(RegexCache.regex(source, options: [.caseInsensitive]))
        #expect(plain !== insensitive)
        #expect(insensitive.options.contains(.caseInsensitive))
    }

    /// A pattern built from page content can be malformed; that has to come
    /// back as nil rather than as a crash or a stale hit.
    @Test("Un pattern non valido torna nil")
    func invalidPattern() {
        #expect(RegexCache.regex("[unclosed") == nil)
    }

    @Test("L’espressione tornata funziona come una compilata a mano")
    func stillMatches() throws {
        let regex = try #require(RegexCache.regex(#"(\d{6})"#))
        let text = "Corso 085923 — Architetture"
        let match = try #require(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        #expect((text as NSString).substring(with: match.range) == "085923")
    }

    /// The scrapers run off the main thread and several at a time; the cache
    /// sits behind a lock for exactly this.
    @Test("Richieste in parallelo non si disturbano")
    func concurrentUse() async {
        let sources = (0..<8).map { pattern("-\($0)") }
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<64 {
                for source in sources {
                    group.addTask { RegexCache.regex(source) != nil }
                }
            }
            for await compiled in group { #expect(compiled) }
        }
    }
}
