import Foundation
import Testing
@testable import PoliVerse

/// New and changed items on a WeBeep course page, from two listings.
///
/// Moodle's listing carries a modification time and a size per file, so a
/// change is visible without downloading anything. What matters is turning
/// "a file appeared" into the few kinds a student acts on — results,
/// solutions, a notice — and staying quiet about the rest.
@Suite("Material change detector")
struct MaterialChangeDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)
    private let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")

    private func file(_ module: Int, _ name: String, section: String = "Materiale",
                      size: Int = 100, modified: Int = 1_700_000_000) -> MoodleSection {
        MoodleSection(id: 1, name: section, modules: [
            MoodleModule(id: module, name: name, modname: "resource", contents: [
                MoodleContent(type: "file", filename: name, filesize: size,
                              fileurl: "https://webeep.polimi.it/f/\(module)", timemodified: modified,
                              mimetype: "application/pdf"),
            ]),
        ])
    }

    private func detect(_ previous: MaterialSnapshot?, _ sections: [MoodleSection],
                        sitting: MaterialContext = .none, at time: Date? = nil) -> MaterialChangeDetector.Result {
        MaterialChangeDetector.detect(
            previous: previous, current: MaterialItem.items(from: sections),
            course: course, context: sitting, now: time ?? now)
    }

    private func baseline(_ sections: [MoodleSection]) -> MaterialSnapshot {
        detect(nil, sections).snapshot
    }

    @Test("Items are flattened per file, labels skipped, and tagged")
    func flatten() {
        let sections = [
            file(1, "Lezione 01.pdf"),
            MoodleSection(id: 2, name: "Esami", modules: [
                MoodleModule(id: 2, name: "Benvenuti", modname: "label", contents: nil),
                MoodleModule(id: 3, name: "Consegna progetto", modname: "assign", contents: nil),
            ]),
        ]
        let items = MaterialItem.items(from: sections)
        #expect(items.map(\.id) == ["cm:1/Lezione 01.pdf", "cm:3"])
        #expect(items[0].tags == [.lectureMaterial])
        #expect(items[1].tags.contains(.assignment))
    }

    @Test("The first listing is a silent baseline")
    func silentBaseline() {
        let result = detect(nil, [file(1, "Esiti.pdf")])
        #expect(result.updates.isEmpty)
        #expect(result.snapshot.versions.count == 1)
    }

    @Test("A new results file, solutions file or notice is named for what it is")
    func notable() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        #expect(detect(base, [file(1, "Lezione 01.pdf"), file(2, "Esiti 31-08-2026.pdf")])
                    .updates.map(\.kind) == [.resultsPosted])
        #expect(detect(base, [file(1, "Lezione 01.pdf"), file(2, "Soluzioni appello.pdf")])
                    .updates.map(\.kind) == [.solutionsPosted])
        #expect(detect(base, [file(1, "Lezione 01.pdf"), file(2, "Suddivisione aule.pdf")])
                    .updates.map(\.kind) == [.examNoticePosted])
    }

    /// Solutions to an exercise sheet are not an exam's solutions.
    @Test("Exercise solutions are ordinary material")
    func exerciseSolutions() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        #expect(detect(base, [file(1, "Lezione 01.pdf"), file(2, "Esercitazione 3 soluzioni.pdf")])
                    .updates.map(\.kind) == [.materialAdded])
    }

    /// A teacher uploading twenty slides is one piece of news.
    @Test("Ordinary new files in one listing become a single update")
    func coalesced() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        let result = detect(base, [file(1, "Lezione 01.pdf"), file(2, "Lezione 02.pdf"), file(3, "Lezione 03.pdf")])
        #expect(result.updates.map(\.kind) == [.materialAdded])
        #expect(result.updates.first?.newValue == "2")
    }

    /// A corrected results file is uploaded over the old one (§19, case 10).
    @Test("A results file replaced with a new version is recorded as a correction")
    func replacedResults() {
        let base = baseline([file(2, "Esiti.pdf", modified: 1)])
        let result = detect(base, [file(2, "Esiti.pdf", modified: 2)])
        #expect(result.updates.map(\.kind) == [.resultsPosted])
        #expect(result.updates.first?.isReplacement == true)
        #expect(detect(base, [file(2, "Esiti.pdf", modified: 1)]).updates.isEmpty)
    }

    /// "Esiti" renamed "Esiti_corretti_v2" (§19, case 11).
    @Test("A results file renamed is a correction, not a second results file")
    func renamedResults() {
        let base = baseline([file(1, "Lezione 01.pdf"), file(2, "Esiti.pdf")])
        let result = detect(base, [file(1, "Lezione 01.pdf"), file(3, "Esiti_corretti_v2.pdf")])
        #expect(result.updates.map(\.kind) == [.resultsPosted])
        #expect(result.updates.first?.isReplacement == true)
    }

    @Test("A name that says both results and solutions is only probable")
    func ambiguous() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        let update = detect(base, [file(1, "Lezione 01.pdf"), file(2, "Soluzioni e risultati.pdf")]).updates.first
        #expect(update?.kind == .resultsPosted)
        #expect(update?.confidence == .probable)
    }

    /// Otherwise a page last opened in October announces October-to-February
    /// as news in February.
    @Test("A listing compared against an old snapshot is a new baseline")
    func stale() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        let later = now.addingTimeInterval(MaterialChangeDetector.staleAfter + 60)
        #expect(detect(base, [file(1, "Lezione 01.pdf"), file(2, "Esiti.pdf")], at: later).updates.isEmpty)
    }

    @Test("A lecture replaced with a new version says nothing")
    func replacedLecture() {
        let base = baseline([file(1, "Lezione 01.pdf", modified: 1)])
        #expect(detect(base, [file(1, "Lezione 01.pdf", modified: 2)]).updates.isEmpty)
    }

    @Test("An empty listing is not every file removed")
    func emptyListing() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        let result = detect(base, [])
        #expect(result.updates.isEmpty)
        #expect(result.snapshot == base)
    }

    @Test("Updates carry the course, the file and the sitting they may concern")
    func context() {
        let base = baseline([file(1, "Lezione 01.pdf")])
        let exam = now.addingTimeInterval(-3 * 86400)
        let next = now.addingTimeInterval(5 * 86400)
        let updates = detect(base, [file(1, "Lezione 01.pdf"), file(9, "Esiti.pdf"), file(10, "Istruzioni prova.pdf")],
                             sitting: MaterialContext(lastSat: exam, next: next)).updates
        let update = updates.first
        // A notice concerns the sitting ahead, results the one just taken.
        #expect(updates.last?.examDate == next)
        #expect(update?.courseCode == "097785")
        #expect(update?.source == .webeep)
        #expect(update?.confidence == .high)
        #expect(update?.newValue == "Esiti.pdf")
        #expect(update?.wasEnrolled == true)
        #expect(update?.examDate == exam)
        #expect(update?.evidence.contains("cm=9") == true)
    }
}
