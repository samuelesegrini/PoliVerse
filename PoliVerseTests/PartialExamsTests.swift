import Foundation
import Testing
@testable import PoliVerse

/// Prove in itinere: what the scheda says, which sittings are partial exams,
/// and what the teacher wrote about them. Nothing here computes a final mark —
/// only the teacher's text says how the parts count.
@Suite("Prove in itinere")
struct PartialExamsTests {
    @Test("The scheda's standard wording decides whether a course has them", arguments: [
        (["Prova scritta obbligatoria, senza prove in itinere"], PartialExams.Policy.none),
        (["Prova scritta obbligatoria, con prove in itinere"], .offered),
        (["Prova scritta facoltativa, in sostituzione dell'esame con prove in itinere"], .offered),
        (["Prova orale obbligatoria"], .unknown),
        ([], .unknown),
    ])
    func policy(assessment: [String], expected: PartialExams.Policy) {
        #expect(PartialExams.policy(assessment: assessment, notes: nil) == expected)
    }

    @Test("A teacher's notes mentioning midterms count when the list says nothing")
    func notesOffered() {
        #expect(PartialExams.policy(assessment: ["Prova orale obbligatoria"],
                                    notes: "There will be two midterm exams replacing the final written test.")
            == .offered)
    }

    @Test("Only the sentences about partial exams are quoted from the notes")
    func quotedSentences() {
        let notes = "L'esame è scritto. Sono previste due prove in itinere a novembre e gennaio. Il voto è in trentesimi."
        #expect(PartialExams.sentences(in: notes) == ["Sono previste due prove in itinere a novembre e gennaio."])
    }

    private func sitting(_ id: Int, kind: String?) -> ExamSession {
        ExamSession(id: id, courseName: "ANALISI", courseCode: "1", teacher: nil, date: nil, room: nil,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil, kind: kind, status: .closed)
    }

    @Test("Sittings whose type names a partial exam are picked out")
    func partialSittings() {
        let sittings = [sitting(1, kind: "Appello d'esame"), sitting(2, kind: "Prova in itinere"),
                        sitting(3, kind: "PROVA INTERMEDIA"), sitting(4, kind: nil), sitting(5, kind: "Prova parziale")]
        #expect(PartialExams.sittings(sittings).map(\.id) == [2, 3, 5])
    }
}
