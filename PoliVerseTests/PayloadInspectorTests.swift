import Foundation
import Testing
@testable import PoliVerse

/// The diagnostic screen's reading of a payload: every field once, its type,
/// a masked sample, and whether it looks like a degree course or plan code.
@Suite("Payload inspector")
struct PayloadInspectorTests {
    private func value(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("Fields of every array element are listed once, by path")
    func flatten() throws {
        let fields = PayloadInspector.fields(in: try value(#"""
        [{"matricola":"986617","desc_tipo_carriera":{"it":"Laurea"}},
         {"matricola":"337940","k_corso_la":542,"extra":null}]
        """#))
        #expect(fields.map(\.path) == ["[].desc_tipo_carriera.it", "[].extra", "[].k_corso_la", "[].matricola"])
        #expect(fields.first { $0.path == "[].k_corso_la" }?.type == "number")
        #expect(fields.first { $0.path == "[].extra" }?.type == "null")
    }

    @Test("Samples keep their shape and hide their content")
    func mask() {
        #expect(PayloadInspector.mask("IT1") == "AA9")
        #expect(PayloadInspector.mask("Rossi Mario") == "Aaaaa Aaaaa")
        #expect(PayloadInspector.mask("2026/2027") == "9999/9999")
    }

    @Test("Fields that could be the programme's codes are flagged")
    func interesting() {
        #expect(PayloadInspector.isInteresting("k_corso_la"))
        #expect(PayloadInspector.isInteresting("[].codiceCDL"))
        #expect(PayloadInspector.isInteresting("c_classe_m"))
        #expect(PayloadInspector.isInteresting("descrizioneIndirizzo"))
        #expect(!PayloadInspector.isInteresting("voto_esame"))
    }

    @Test("The report lists fields with masked samples, never raw values unless asked")
    func report() throws {
        let fields = PayloadInspector.fields(in: try value(#"{"k_indir":"IT1","nome":"Mario"}"#))
        let masked = PayloadInspector.report(title: "testatapiano", fields: fields, showValues: false)
        #expect(masked.contains("k_indir: string = AA9  ★"))
        #expect(!masked.contains("Mario"))
        #expect(PayloadInspector.report(title: "x", fields: fields, showValues: true).contains("IT1"))
    }

    @Test("A class's scheda confirms the exam lecturer when a name matches in any order")
    func lecturer() {
        #expect(PayloadInspector.sameLecturer(exam: "CAMILLI MATTEO", scheda: ["Camilli Matteo"]))
        #expect(PayloadInspector.sameLecturer(exam: "Matteo Camilli", scheda: ["Di Nitto Elisabetta", "Camilli Matteo"]))
        #expect(!PayloadInspector.sameLecturer(exam: "Rossi Matteo Giovanni", scheda: ["Camilli Matteo"]))
    }
}
