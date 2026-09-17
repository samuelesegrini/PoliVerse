import Foundation
import Testing
@testable import PoliVerse

/// `JSONShape` exists to describe a payload nobody has captured — the
/// notifications endpoint — from a device run, without the payload itself
/// ever reaching a log. These pin both halves: the description is accurate,
/// and no value from the payload appears in it.
@Suite("Forma di un payload")
struct JSONShapeTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("Un oggetto è descritto per chiavi ordinate e tipi")
    func object() {
        let described = JSONShape.describe(data(#"{"id_notice":12,"data_inserimento":"2026-03-01","letto":false}"#))
        #expect(described == "object{data_inserimento: string, id_notice: number, letto: bool}")
    }

    /// The lists these endpoints send are homogeneous, so one element stands
    /// for all of them and the count says how many there were.
    @Test("Una lista è descritta dal primo elemento e dalla sua lunghezza")
    func array() {
        let described = JSONShape.describe(data(#"[{"a":1},{"a":2},{"a":3}]"#))
        #expect(described == "array[3] of object{a: number}")
    }

    @Test("Una lista vuota non pretende di conoscere i suoi elementi")
    func emptyArray() {
        #expect(JSONShape.describe(data("[]")) == "array[0]")
    }

    /// Nested values are named by type only: enough to tell a plain string
    /// from the `{it, en}` pairs these services use for labels.
    @Test("Un valore annidato è descritto a un livello di profondità")
    func nested() {
        let described = JSONShape.describe(data(#"{"desc":{"it":"Laurea","en":"Bachelor"},"tags":[1,2]}"#))
        #expect(described == "object{desc: object{en,it}, tags: array[2]}")
    }

    /// The reason the type exists: a notification's text is the student's own
    /// mail. The description must carry none of it.
    @Test("Nessun valore del payload finisce nella descrizione")
    func neverLeaksValues() {
        let payload = #"{"oggetto":"Esito di Analisi 2: 27","mittente":"rossi@polimi.it","voto":27}"#
        let described = JSONShape.describe(data(payload))
        #expect(!described.contains("Analisi"))
        #expect(!described.contains("rossi@polimi.it"))
        #expect(!described.contains("27"))
        #expect(described.contains("oggetto: string"))
    }

    /// Past `maxKeys` the description says how many more there were rather
    /// than growing without bound.
    @Test("Oltre il limite di chiavi la descrizione dice quante ne restano")
    func manyKeys() {
        let fields = (1...10).map { "\"k\($0)\":1" }.joined(separator: ",")
        let described = JSONShape.describe(data("{\(fields)}"), maxKeys: 3)
        #expect(described.hasSuffix("…+7}"))
        #expect(described.hasPrefix("object{k1: number, k10: number, k2: number"))
    }

    /// A body that is not JSON at all — an HTML error page, a login redirect —
    /// is the common failure, and it is named as such with its size.
    @Test("Un corpo che non è JSON è detto illeggibile, con la sua dimensione")
    func unparseable() {
        let html = "<html><body>Errore</body></html>"
        #expect(JSONShape.describe(Data(html.utf8)) == "unparseable (\(html.utf8.count) bytes)")
    }
}
