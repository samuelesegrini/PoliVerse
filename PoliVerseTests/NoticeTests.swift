import Foundation
import Testing
@testable import PoliVerse

/// The notifications payload was never captured from a real account, so the
/// decoder is written against candidate field names rather than known ones.
/// These pin the behaviour that has to hold whichever guess turns out right:
/// a wrong name costs one field, never the whole list.
@Suite("Notifications")
struct NoticeTests {
    private func notices(_ json: String) -> [Notice] {
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode(NoticesResponse.self, from: data))?.notices ?? []
    }

    @Test("A bare array of Italian-named rows decodes")
    func italianNames() {
        let parsed = notices("""
        [{"id_notice": 4412, "titolo": "Esito disponibile",
          "testo": "Il risultato è consultabile.",
          "data_inserimento": "2026-01-12 09:30:00", "letto": false}]
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].id == "4412")
        #expect(parsed[0].title == "Esito disponibile")
        #expect(parsed[0].serverRead == false)
        #expect(parsed[0].date != nil)
    }

    @Test("English-named rows decode the same way")
    func englishNames() {
        let parsed = notices("""
        [{"id": "a-1", "title": "Second instalment",
          "body": "Due 31 March.", "read": true}]
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].title == "Second instalment")
        #expect(parsed[0].serverRead == true)
    }

    /// The agenda sends every label as `{it, en}`; this endpoint may too.
    @Test("A localised title is read, preferring Italian")
    func localisedTitle() {
        let parsed = notices("""
        [{"id_notice": 1, "title": {"it": "Avviso", "en": "Notice"}}]
        """)
        #expect(parsed[0].title == "Avviso")
    }

    /// `/v1/insegn` wraps its array in a key; the agenda does not. Both
    /// conventions are in use, so both must work.
    @Test("An array behind a wrapper key is found")
    func wrappedArray() {
        let parsed = notices("""
        {"notifiche": [{"id_notice": 7, "titolo": "Uno"},
                       {"id_notice": 8, "titolo": "Due"}]}
        """)
        #expect(parsed.count == 2)
    }

    @Test("An array behind an unguessed key is still found")
    func unknownWrapperKey() {
        let parsed = notices("""
        {"totale": 1, "ELENCO_AVVISI_UTENTE": [{"id_notice": 9, "titolo": "Tre"}]}
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].title == "Tre")
    }

    /// The failure this whole design exists to prevent: one odd row taking the
    /// rest of the list down with it, which is how the libretto broke.
    @Test("An unreadable row is dropped, not the whole list")
    func oneBadRowDoesNotSinkTheRest() {
        let parsed = notices("""
        [{"id_notice": 1, "titolo": "Buona"},
         {"qualcosa": {"di": "inatteso"}},
         {"id_notice": 3, "titolo": "Anche buona"}]
        """)
        #expect(parsed.count == 2)
    }

    @Test("A row with a title but no id still shows, with a distinct identity")
    func missingIDStillShows() {
        let parsed = notices("""
        [{"titolo": "Senza id"}, {"titolo": "Anche senza"}]
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].id != parsed[1].id)
    }

    @Test("Epoch milliseconds and seconds are told apart")
    func epochMagnitude() {
        // The libretto sends milliseconds, other services send seconds.
        let millis = Notice.date(from: .number(1_768_210_200_000))
        let seconds = Notice.date(from: .number(1_768_210_200))
        #expect(millis == seconds)
    }

    @Test("An ISO 8601 timestamp is accepted")
    func isoTimestamps() {
        #expect(Notice.date(from: .string("2026-01-12T09:30:00Z")) != nil)
        #expect(Notice.date(from: .string("2026-01-12T09:30:00.500Z")) != nil)
    }

    @Test("An unread flag is inverted rather than ignored")
    func unreadInverted() {
        #expect(Notice.readFlag(in: ["non_letto": .bool(true)]) == false)
        #expect(Notice.readFlag(in: ["unread": .bool(false)]) == true)
    }

    @Test("A read timestamp means read; an empty one does not")
    func readTimestamp() {
        #expect(Notice.readFlag(in: ["data_lettura": .string("2026-01-12")]) == true)
        #expect(Notice.readFlag(in: ["data_lettura": .string("")]) == false)
    }

    @Test("Field names are matched ignoring case and underscores")
    func looseKeyMatching() {
        let parsed = notices("""
        [{"idNotice": 5, "Titolo": "Maiuscola", "dataInserimento": 1768210200}]
        """)
        #expect(parsed[0].id == "5")
        #expect(parsed[0].title == "Maiuscola")
        #expect(parsed[0].date != nil)
    }
}

/// The shape log is what turns the guesses above into facts after one device
/// run, so it has to describe structure — and must never print content.
@Suite("JSON shape")
struct JSONShapeTests {
    @Test("An array of objects is summarised by its first element")
    func arrayOfObjects() {
        let data = Data("""
        [{"id_notice": 1, "titolo": "Esito esame di Analisi"},
         {"id_notice": 2, "titolo": "Scadenza rata"}]
        """.utf8)
        let shape = JSONShape.describe(data)
        #expect(shape == "array[2] of object{id_notice: number, titolo: string}")
    }

    /// A notification is the student's own mail. The log gets pasted into
    /// chats and bug reports, so no value may ever reach it.
    @Test("No value from the payload appears in the description")
    func valuesNeverLeak() {
        let data = Data("""
        [{"titolo": "Esito: respinto", "matricola": "10812345",
          "nested": {"testo": "segreto"}}]
        """.utf8)
        let shape = JSONShape.describe(data)
        #expect(!shape.contains("respinto"))
        #expect(!shape.contains("10812345"))
        #expect(!shape.contains("segreto"))
        #expect(shape.contains("titolo"))
    }

    @Test("An empty array says so rather than guessing an element type")
    func emptyArray() {
        #expect(JSONShape.describe(Data("[]".utf8)) == "array[0]")
    }

    @Test("A body that is not JSON is reported as such")
    func unparseable() {
        #expect(JSONShape.describe(Data("<html>502</html>".utf8)).hasPrefix("unparseable"))
    }
}
