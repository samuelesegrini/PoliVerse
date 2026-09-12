import Foundation
import Testing
@testable import PoliVerse

/// How a query is compared to a result.
///
/// `localizedCaseInsensitiveContains` was the old rule and it is too strict in
/// one direction and too loose in the other: it misses "informatica" typed
/// without the accent it never had, and it ranks a course whose title merely
/// contains the word above one that starts with it.
@Suite("Search matching")
struct SearchMatchingTests {
    @Test("Matching ignores case and diacritics")
    func diacritics() {
        #expect(SearchMatch.matches("informatici", in: "Sistemi Informàtici"))
        #expect(SearchMatch.matches("PERCHE", in: "Perché studiare"))
        #expect(SearchMatch.matches("citta", in: "Città Studi"))
    }

    /// Two words typed in any order should still find one title containing
    /// both — the old single-substring rule failed on "basi dati".
    @Test("Every word must appear, in any order")
    func allWordsAnyOrder() {
        #expect(SearchMatch.matches("basi dati", in: "Basi di Dati"))
        #expect(SearchMatch.matches("dati basi", in: "Basi di Dati"))
        #expect(!SearchMatch.matches("basi reti", in: "Basi di Dati"))
    }

    @Test("Extra whitespace does not change the result")
    func whitespace() {
        #expect(SearchMatch.matches("  basi   dati ", in: "Basi di Dati"))
        #expect(!SearchMatch.matches("   ", in: "Basi di Dati"))
    }

    @Test("Several fields are searched together")
    func multipleFields() {
        #expect(SearchMatch.matches("rossi", in: "Analisi", "Maria Rossi"))
        #expect(SearchMatch.matches("analisi rossi", in: "Analisi", "Maria Rossi"))
    }

    /// Ranking: a prefix beats a word start, which beats a match buried inside
    /// a word. Without it "ana" put "Metodi Analitici" above "Analisi".
    @Test("A prefix ranks above a word start, which ranks above a substring")
    func ranking() {
        let prefix = SearchMatch.score("ana", in: "Analisi Matematica")
        let wordStart = SearchMatch.score("ana", in: "Metodi Analitici")
        let inside = SearchMatch.score("ana", in: "Bioingegneria Anatomica")
        #expect(prefix > wordStart)
        #expect(wordStart > inside)
    }

    @Test("A non-match scores nothing")
    func noMatch() {
        #expect(SearchMatch.score("fisica", in: "Analisi Matematica") == 0)
    }

    /// An exact hit on a room code has to win: someone typing "3.0.1" wants
    /// that room, not every course whose description mentions it.
    @Test("An exact match outranks everything else")
    func exactWins() {
        let exact = SearchMatch.score("3.0.1", in: "3.0.1")
        let partial = SearchMatch.score("3.0.1", in: "Aula 3.0.1 — Edificio 3")
        #expect(exact > partial)
    }

    @Test("Results sort by score, then alphabetically")
    func sorting() {
        let ranked = SearchMatch.rank(
            ["Metodi Analitici", "Analisi Matematica", "Analisi Numerica"],
            query: "ana") { $0 }
        #expect(ranked.first == "Analisi Matematica")
        #expect(ranked.last == "Metodi Analitici")
    }

    @Test("Ranking drops what does not match at all")
    func rankingFilters() {
        let ranked = SearchMatch.rank(["Analisi", "Fisica"], query: "ana") { $0 }
        #expect(ranked == ["Analisi"])
    }
}

/// Spotlight hands back only the identifier string, possibly long after the
/// app last ran, so it has to carry enough to route on by itself.
@Suite("Spotlight identifiers")
struct SpotlightIdentifierTests {
    @Test("Every kind round-trips through its identifier")
    func roundTrip() {
        let items: [SpotlightIndex.Item] = [
            .course("moodle-123"), .room("3.0.1"),
            .teacher("maria rossi"), .exam("app-9"),
        ]
        for item in items {
            #expect(SpotlightIndex.Item(identifier: item.identifier) == item)
        }
    }

    /// Room codes and Moodle ids contain colons and dots; splitting on the
    /// first colon only is what keeps them intact.
    @Test("An identifier containing a colon survives")
    func colonInValue() {
        let item = SpotlightIndex.Item.course("a:b:c")
        #expect(SpotlightIndex.Item(identifier: item.identifier) == .course("a:b:c"))
    }

    @Test("Nonsense is rejected rather than routed somewhere wrong")
    func rejectsGarbage() {
        #expect(SpotlightIndex.Item(identifier: "") == nil)
        #expect(SpotlightIndex.Item(identifier: "nocolon") == nil)
        #expect(SpotlightIndex.Item(identifier: "unknown:1") == nil)
    }
}

/// Ranking over the app's own kinds of result, which is where the scoring has
/// to earn its keep.
@Suite("Search ranking")
struct SearchRankingTests {
    private func course(_ name: String, teacher: String = "—", code: String? = nil) -> Course {
        Course(id: code ?? name, name: name, teacher: teacher, cfu: 5,
               semester: "1", academicYear: "2025/26", code: code)
    }

    /// The case that motivated scoring: a title that begins with the query
    /// must beat one that merely contains it.
    @Test("A course starting with the query comes first")
    func coursePrefixWins() {
        let ranked = SearchMatch.rank(
            [course("Metodi Analitici"), course("Analisi Matematica")],
            query: "analisi") { [$0.name, $0.teacher] }
        #expect(ranked.first?.name == "Analisi Matematica")
    }

    @Test("A course is findable by its teacher and its code")
    func otherFields() {
        let courses = [course("Basi di Dati", teacher: "Maria Rossi", code: "097785")]
        #expect(!SearchMatch.rank(courses, query: "rossi") { [$0.name, $0.teacher, $0.code ?? ""] }.isEmpty)
        #expect(!SearchMatch.rank(courses, query: "097785") { [$0.name, $0.teacher, $0.code ?? ""] }.isEmpty)
    }

    /// Typing a room code exactly should not be buried under courses whose
    /// description happens to mention it.
    @Test("An exact room code outranks a mention of it")
    func roomCodeExact() {
        let ranked = SearchMatch.rank(
            ["Laboratorio in aula 3.0.1 con proiettore", "3.0.1"],
            query: "3.0.1") { [$0] }
        #expect(ranked.first == "3.0.1")
    }

    @Test("Multi-word queries find titles with the words apart")
    func multiWord() {
        let ranked = SearchMatch.rank(
            [course("Basi di Dati"), course("Reti Logiche")],
            query: "basi dati") { [$0.name] }
        #expect(ranked.count == 1)
        #expect(ranked.first?.name == "Basi di Dati")
    }

    @Test("Ranking is stable for equal scores")
    func stability() {
        let first = SearchMatch.rank(["Bravo", "Alfa"], query: "a") { [$0] }
        let again = SearchMatch.rank(["Alfa", "Bravo"], query: "a") { [$0] }
        #expect(first == again)
    }
}
