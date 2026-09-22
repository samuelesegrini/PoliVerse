import Foundation
import Testing
@testable import PoliVerse

/// The corrections reader is tested harder than most, because the shape it
/// reads is not verified: `docs/polimi-api-research.md` §4c says every shape on
/// that host is inferred. These cases pin the behaviour that matters — read
/// what can be read, never trap, never invent a row.
@Suite("Corrections")
struct CorrectionsTests {
    /// Decodes a JSON literal the way the reader receives it.
    ///
    /// - Parameter json: The body.
    /// - Returns: The decoded value.
    private func body(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("A bare array is the list")
    func bareArray() throws {
        let rows = CorrectionsSource.list(in: try body(#"[{"id":"1"},{"id":"2"}]"#))
        #expect(rows.count == 2)
    }

    @Test("A list wrapped in an object is found under any of the names it might carry",
          arguments: ["correzioni", "elenco", "data", "items", "list", "result"])
    func wrapped(key: String) throws {
        let rows = CorrectionsSource.list(in: try body(#"{"\#(key)":[{"id":"1"}]}"#))
        #expect(rows.count == 1)
    }

    @Test("A shape with no list anywhere is no rows, not a crash")
    func unknownShape() throws {
        #expect(CorrectionsSource.list(in: try body(#"{"messaggio":"nessun elaborato"}"#)).isEmpty)
        #expect(CorrectionsSource.list(in: try body("null")).isEmpty)
        #expect(CorrectionsSource.list(in: try body("42")).isEmpty)
    }

    @Test("Fields are read under any of their candidate spellings")
    func fields() throws {
        let row = try body(#"""
            {"idCorrezione": 77, "nomeFile": "compito.pdf",
             "dataPubblicazione": "2026-02-12T09:00:00", "mimeType": "application/pdf"}
            """#)
        let correction = try #require(CorrectionsSource.correction(row))
        #expect(correction.id == "77")
        #expect(correction.name == "compito.pdf")
        #expect(correction.contentType == "application/pdf")
        #expect(correction.date != nil)
    }

    @Test("Everything but the id may be missing")
    func idOnly() throws {
        let correction = try #require(CorrectionsSource.correction(try body(#"{"id":"9"}"#)))
        #expect(correction.name == nil)
        #expect(correction.date == nil)
        // The screen still has something to call it.
        #expect(!correction.title.isEmpty)
    }

    @Test("A row with no id is not a row: there would be nothing to open")
    func idless() throws {
        #expect(CorrectionsSource.correction(try body(#"{"nome":"compito.pdf"}"#)) == nil)
        #expect(CorrectionsSource.correction(try body(#"{"id":""}"#)) == nil)
        #expect(CorrectionsSource.correction(try body(#""stringa""#)) == nil)
    }

    @Test("An unparseable date is no date, not a wrong one")
    func badDate() throws {
        let correction = try #require(
            CorrectionsSource.correction(try body(#"{"id":"1","data":"non una data"}"#)))
        #expect(correction.date == nil)
    }
}
