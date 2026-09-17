import Foundation
import Testing
@testable import PoliVerse

/// How deep a payload's description goes.
///
/// The arrays, the privacy rule and the unreadable body are pinned in
/// `NoticeTests`; this is the other half — objects, one level of nesting, and
/// the ceiling on how many keys a description may grow to.
@Suite("Profondità della forma di un payload")
struct JSONShapeDepthTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("Un oggetto è descritto per chiavi ordinate e tipi")
    func object() {
        let described = JSONShape.describe(data(#"{"id_notice":12,"data_inserimento":"2026-03-01","letto":false}"#))
        #expect(described == "object{data_inserimento: string, id_notice: number, letto: bool}")
    }

    /// One level, not a tree: enough to tell a plain string from the
    /// `{it, en}` pairs these services use for labels, without printing the
    /// whole payload's skeleton.
    @Test("Un valore annidato è descritto a un livello di profondità")
    func nested() {
        let described = JSONShape.describe(data(#"{"desc":{"it":"Laurea","en":"Bachelor"},"tags":[1,2]}"#))
        #expect(described == "object{desc: object{en,it}, tags: array[2]}")
    }

    /// Past the ceiling the description says how many keys are left rather
    /// than growing without bound — these payloads are read in a log line.
    @Test("Oltre il limite di chiavi la descrizione dice quante ne restano")
    func manyKeys() {
        let fields = (1...10).map { "\"k\($0)\":1" }.joined(separator: ",")
        let described = JSONShape.describe(data("{\(fields)}"), maxKeys: 3)
        #expect(described.hasPrefix("object{k1: number, k10: number, k2: number"))
        #expect(described.hasSuffix("…+7}"))
    }

    @Test("Entro il limite non c’è nessun avanzo da segnalare")
    func withinTheLimit() {
        #expect(!JSONShape.describe(data(#"{"a":1,"b":2}"#), maxKeys: 40).contains("…"))
    }
}
