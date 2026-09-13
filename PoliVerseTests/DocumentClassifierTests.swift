import Foundation
import Testing
@testable import PoliVerse

/// What a file on WeBeep is, from its name and where the teacher put it.
///
/// Rules only, no model: a teacher's naming is inconsistent but not
/// adversarial, and a rule that fires can say why. The cases below are the
/// shapes real course pages use; the false positives are the ones that would
/// cost a student a wrong "results published" at eleven at night.
@Suite("Document classifier")
struct DocumentClassifierTests {
    private func tags(_ name: String, section: String = "Materiale", module: String? = nil,
                      modname: String = "resource", mimetype: String? = nil) -> Set<DocumentTag> {
        DocumentClassifier.tags(
            fileName: name, moduleName: module ?? name, sectionName: section,
            modname: modname, mimetype: mimetype)
    }

    @Test("Results files, however they are spelled", arguments: [
        "Esiti_31_08_2026.pdf", "Risultati Appello 12-07-26.xlsx", "Valutazioni prova in itinere.pdf",
        "voti-scritto.csv", "Results_exam_June.pdf", "ESITI.PDF", "Ammessi all'orale.pdf",
    ])
    func results(_ name: String) {
        #expect(tags(name).contains(.results))
    }

    @Test("Solutions files", arguments: [
        "Soluzioni_appello_2026-08-31.pdf", "Tema d'esame svolto.pdf", "correzione compito.pdf",
        "Exam_solutions.pdf", "Esercizi risolti.pdf",
    ])
    func solutions(_ name: String) {
        #expect(tags(name).contains(.solutions))
    }

    @Test("An exam text is not its solutions")
    func examText() {
        #expect(tags("Testo appello 31 agosto.pdf") == [.examText])
        #expect(!tags("Testo e soluzioni appello.pdf").contains(.examText))
    }

    @Test("Notices about rooms and instructions", arguments: [
        "Suddivisione aule per cognome.pdf", "Istruzioni per la prova.pdf", "Avviso esame.pdf",
        "Convocazioni orali.pdf",
    ])
    func notices(_ name: String) {
        #expect(tags(name).contains(.examNotice))
    }

    /// "Risultati di apprendimento" is how every syllabus names its learning
    /// outcomes.
    @Test("A syllabus is not a results file")
    func syllabus() {
        #expect(!tags("Programma e risultati di apprendimento attesi.pdf").contains(.results))
        #expect(tags("Programma del corso.pdf").contains(.admin))
    }

    @Test("A name with both results and solutions carries both")
    func both() {
        #expect(tags("Soluzioni e risultati.pdf").isSuperset(of: [.results, .solutions]))
    }

    @Test("Exercise solutions are exercises too")
    func exerciseSolutions() {
        #expect(tags("Esercitazione 3 - soluzioni.pdf") == [.exercise, .solutions])
    }

    @Test("Lecture material, recordings and assignments")
    func ordinary() {
        #expect(tags("Lezione 04 - Normalizzazione.pdf") == [.lectureMaterial])
        #expect(tags("slides_week2.pptx") == [.lectureMaterial])
        #expect(tags("registrazione.mp4", mimetype: "video/mp4") == [.recording])
        #expect(tags("Consegna progetto", modname: "assign") == [.assignment])
        #expect(tags("dispensa.pdf").contains(.lectureMaterial))
        #expect(tags("foto.jpg").isEmpty)
    }

    /// The section is where the teacher already said what it is.
    @Test("The section and module name count, not just the file name")
    func context() {
        #expect(tags("2026-08-31.pdf", module: "Esiti appello di agosto").contains(.results))
        #expect(tags("file.pdf", section: "Aule e istruzioni").contains(.examNotice))
    }
}

@Suite("Document classifier · §9.2 coverage")
struct DocumentClassifierCoverageTests {
    @Test("Exam timetables are notices; 'esercizi' and 'lab' are exercises")
    func coverage() {
        func tags(_ name: String) -> Set<DocumentTag> {
            DocumentClassifier.tags(fileName: name, moduleName: name, sectionName: "",
                                    modname: "resource", mimetype: nil)
        }
        #expect(tags("Orario dell'esame.pdf").contains(.examNotice))
        #expect(tags("Esercizi risolti.pdf").isSuperset(of: [.exercise, .solutions]))
        #expect(tags("Lab 3.pdf").contains(.exercise))
    }
}
