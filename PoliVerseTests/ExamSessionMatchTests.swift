import Foundation
import Testing
@testable import PoliVerse

/// Deciding whether a sitting belongs to a course.
///
/// Harder than it sounds: WeBeep's title code, the libretto's `c_insegn` and
/// `/v1/insegn`'s `c_insegn_piano` are not guaranteed to agree for the same
/// teaching, while the names go through the same normalisation everywhere. So
/// the code decides when it can, and the name is the fallback — a course page
/// showing somebody else's sittings, or none of its own, is what the two get
/// wrong.
@Suite("A quale corso appartiene un appello")
struct ExamSessionMatchTests {
    private func sitting(code: String, name: String) -> ExamSession {
        ExamSession(id: 1, courseName: name, courseCode: code, teacher: nil, date: nil, room: nil,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil, kind: nil,
                    status: .open)
    }

    @Test("Lo stesso codice basta")
    func sameCode() {
        let exam = sitting(code: "097785", name: "Basi di Dati")
        #expect(exam.isOf(courseCode: "097785", courseName: "Basi di Dati"))
        #expect(exam.isOf(courseCode: "097785", courseName: "Tutt’altro nome"),
                "Il codice, quando c’è ed è uguale, decide da solo")
    }

    /// The names are normalised the same way at both ends, so they match even
    /// when one source shouts and the other does not.
    @Test("Codici diversi: decide il nome, normalizzato")
    func differentCodesSameName() {
        let exam = sitting(code: "097785", name: Course.normalise("BASI DI DATI"))
        #expect(exam.isOf(courseCode: "086089", courseName: "BASI DI DATI"))
        #expect(exam.isOf(courseCode: "086089", courseName: "Basi di Dati"))
    }

    /// The bug this rule exists for. Two sittings that arrived without a code
    /// used to count as the same course as each other and as every course
    /// that also lacked one, so one of them appeared under all of them at
    /// once — in the timeline, on the course card and in the course screen.
    @Test("Due codici mancanti non sono lo stesso codice")
    func missingCodesDoNotMatch() {
        let exam = sitting(code: "", name: "Basi di Dati")
        #expect(!exam.isOf(courseCode: "", courseName: "Analisi"))
        #expect(!exam.isOf(courseCode: "", courseName: "Reti Logiche"))
    }

    /// The same holds for the dashes these endpoints use to spell "not
    /// recorded": they are an absence written down, not a value.
    @Test("I trattini con cui i servizi scrivono «non registrato» non combaciano", arguments: ["", " ", "—", "-"])
    func blankCodes(blank: String) {
        let exam = sitting(code: blank, name: "Basi di Dati")
        #expect(!exam.isOf(courseCode: blank, courseName: "Analisi"),
                "Un codice assente «\(blank)» non deve identificare niente")
    }

    /// A sitting with no code is still placed by its name, which is the whole
    /// point of consulting the name at all.
    @Test("Senza codice si decide sul nome, in un senso e nell’altro")
    func withoutACodeTheNameDecides() {
        let exam = sitting(code: "", name: "Basi di Dati")
        #expect(exam.isOf(courseCode: "097785", courseName: "Basi di Dati"))
        #expect(!exam.isOf(courseCode: "097785", courseName: "Analisi"))
    }

    /// And a sitting with no name either belongs to nothing: there is nothing
    /// left to decide on, and guessing would put it under a random course.
    @Test("Senza codice e senza nome non appartiene a niente")
    func withNeither() {
        let exam = sitting(code: "", name: "")
        #expect(!exam.isOf(courseCode: "", courseName: ""))
        #expect(!exam.isOf(courseCode: "097785", courseName: "Basi di Dati"))
    }

    @Test("Né il codice né il nome: non è quel corso")
    func neither() {
        let exam = sitting(code: "097785", name: "Basi di Dati")
        #expect(!exam.isOf(courseCode: "086089", courseName: "Analisi e Geometria 2"))
    }

    /// A sitting whose code nobody agrees on is still placed by its name,
    /// which is the whole reason the name is consulted at all.
    @Test("Un appello il cui codice non combacia si colloca per nome")
    func placedByName() {
        let exam = sitting(code: "c_insegn_piano:097785", name: "Basi di Dati")
        #expect(exam.isOf(courseCode: "097785", courseName: "Basi di Dati"))
        #expect(!exam.isOf(courseCode: "097785", courseName: "Analisi"))
    }

    /// The name is compared without regard to case, because the sources do
    /// not agree about that either.
    @Test("Il confronto sul nome non guarda le maiuscole")
    func caseInsensitiveName() {
        let exam = sitting(code: "A", name: "Basi di Dati")
        #expect(exam.isOf(courseCode: "B", courseName: "basi di dati"))
    }
}
