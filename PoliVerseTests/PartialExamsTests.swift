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

    @Test("Agenda exams named as partial exams join the timeline, lectures do not")
    func agenda() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let events = [
            AgendaEvent(id: 1, title: "Analisi 1 - Prima prova in itinere", start: start, end: start, kind: .exam),
            AgendaEvent(id: 2, title: "Analisi 1 - Appello", start: start, end: start, kind: .exam),
            AgendaEvent(id: 3, title: "Prova in itinere: ripasso", start: start, end: start, kind: .lecture),
        ]
        #expect(PartialExams.agendaEvents(events).map(\.id) == [1])
    }

    @Test("A results file for a partial exam is picked out, with the student's mark when found")
    func resultsFiles() {
        func posted(_ file: String, grade: String?) -> ExamUpdate {
            var update = ExamUpdate(kind: .resultsPosted, examID: nil, courseCode: "1", courseName: "Analisi",
                                    detectedAt: .now, source: .webeep, evidence: "t", newValue: file,
                                    wasEnrolled: false, examDate: nil)
            update.lookup = ResultsLookup(looksLikeResults: true, found: grade != nil, grade: grade)
            return update
        }
        let files = PartialExams.resultsFiles([posted("Risultati prima prova in itinere.pdf", grade: "24"),
                                               posted("Esiti appello febbraio.pdf", grade: "28")])
        #expect(files.map(\.newValue) == ["Risultati prima prova in itinere.pdf"])
        #expect(files.first?.lookup?.grade == "24")
    }
}
