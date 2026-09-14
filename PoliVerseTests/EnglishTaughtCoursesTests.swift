import Foundation
import Testing
@testable import PoliVerse

/// Courses delivered in English: their files, announcements and results lists
/// are written in English, and the rules read both languages — the language
/// of a teaching is per module and per degree, so it is not something to
/// branch on.
@Suite("English-taught courses")
struct EnglishTaughtCoursesTests {
    private func tags(_ name: String, section: String = "Material") -> Set<DocumentTag> {
        DocumentClassifier.tags(fileName: name, moduleName: name, sectionName: section,
                                modname: "resource", mimetype: nil)
    }

    @Test("English file names are tagged like Italian ones", arguments: [
        ("Exam results 12-02-2026.pdf", DocumentTag.results),
        ("Final scores.xlsx", .results),
        ("Admitted to the oral exam.pdf", .results),
        ("Exam solutions.pdf", .solutions),
        ("Answer key midterm.pdf", .solutions),
        ("Past exam paper.pdf", .examText),
        ("Room allocation.pdf", .examNotice),
        ("Exam instructions.pdf", .examNotice),
        ("Exam schedule.pdf", .examNotice),
        ("Tutorial 3.pdf", .exercise),
        ("Problem set 2.pdf", .exercise),
        ("Lecture notes week 4.pdf", .lectureMaterial),
        ("Handout.pdf", .lectureMaterial),
        ("Course syllabus.pdf", .admin),
    ])
    func english(_ name: String, _ tag: DocumentTag) {
        #expect(tags(name).contains(tag))
    }

    @Test("Learning outcomes are not results, in English either")
    func outcomes() {
        #expect(!tags("Syllabus and expected learning outcomes.pdf").contains(.results))
    }

    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func post(_ subject: String, _ message: String = "") -> MoodleDiscussion {
        MoodleDiscussion(id: 1, discussion: 1, name: subject, subject: subject, message: message,
                         created: nil, timemodified: nil, userfullname: nil, pinned: nil)
    }

    @Test("An English announcement about the exam names its date in English", arguments: [
        ("Room allocation for the exam on 2 March", true),
        ("The oral exam of March 2nd is postponed", true),
        ("Written exam: 02/03, bring your ID", true),
        ("Lecture on March 2 moved to room B.3.2", false),
    ])
    func announcements(_ subject: String, _ tied: Bool) {
        let date = PoliMiDate.time(9, on: now.addingTimeInterval(5 * 86400))   // 2 March 2026
        let item = post(subject)
        #expect((AnnouncementDetector.isAboutExams(item) && AnnouncementDetector.mentions(date, in: item)) == tied)
    }

    private let rows = (1...5).map { "91000\($0) X 20" }.joined(separator: "\n")

    @Test("English results lists are read", arguments: [
        ("987654 Rossi Passed", "Superato"),
        ("987654 Rossi FAILED", "Insufficiente"),
        ("987654 Rossi Withdrawn", "Ritirato"),
        ("987654 Rossi Absent", "Assente"),
        ("987654 Rossi Not admitted", "Non ammesso"),
        ("987654 Rossi 30 cum laude", "30L"),
        ("987654 Rossi 30 with honours", "30L"),
    ])
    func results(_ line: String, _ italianLabel: String) {
        let grade = ResultsFileReader.lookup(text: rows + "\n" + line, identifiers: ["987654"]).grade
        let expected = italianLabel == "30L" ? "30L" : String(localized: String.LocalizationValue(italianLabel))
        #expect(grade == expected)
    }

    @Test("English false positives stay out")
    func falsePositives() {
        #expect(!tags("Z-scores and normalisation.pdf").contains(.results))
        let date = PoliMiDate.time(9, on: Date(timeIntervalSince1970: 1_778_000_000))   // 5 May 2026
        let verb = post("Exam prep: exercise 5 may be skipped")
        #expect(!AnnouncementDetector.mentions(date, in: verb))
        #expect(AnnouncementDetector.mentions(date, in: post("Oral exam on 5 May")))
    }

    @Test("A negated or later word does not win over the student's outcome", arguments: [
        ("987654 Rossi Not passed", "Insufficiente"),
        ("987654 Rossi non superato", "Insufficiente"),
        ("987654 Rossi Passed (failed first attempt)", "Superato"),
    ])
    func negations(_ line: String, _ italianLabel: String) {
        let grade = ResultsFileReader.lookup(text: rows + "\n" + line, identifiers: ["987654"]).grade
        #expect(grade == String(localized: String.LocalizationValue(italianLabel)))
    }
}
