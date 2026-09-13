import Foundation
import Testing
@testable import PoliVerse

/// What the feed shows: one row per fact, not one per sighting.
@Suite("Feed items")
struct FeedItemTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func update(_ kind: ExamUpdate.Kind, exam: Int? = 1, course: String = "F1",
                        minutesAgo: Double, source: ExamUpdate.Source = .exams,
                        lookup: ResultsLookup? = nil, value: String? = nil) -> ExamUpdate {
        var update = ExamUpdate(
            kind: kind, examID: exam, courseCode: course, courseName: "Fisica",
            detectedAt: now.addingTimeInterval(-minutesAgo * 60), source: source,
            evidence: "test", newValue: value, wasEnrolled: true, examDate: nil)
        update.lookup = lookup
        return update
    }

    /// A mark nearly always arrives already refusable.
    @Test("A refusal window seen with its mark folds into the mark's row")
    func refusalFolded() {
        let items = FeedItem.items(from: [update(.refusalOpened, minutesAgo: 10),
                                          update(.gradePublished, minutesAgo: 10, value: "27")])
        #expect(items.map(\.update.kind) == [.gradePublished])
        #expect(items.first?.note == String(localized: "Puoi rifiutarlo"))
    }

    @Test("A refusal window opening later keeps its own row")
    func refusalLater() {
        let items = FeedItem.items(from: [update(.refusalOpened, minutesAgo: 10),
                                          update(.gradePublished, minutesAgo: 3 * 24 * 60)])
        #expect(items.map(\.update.kind) == [.refusalOpened, .gradePublished])
    }

    /// §10.4: the exam services win. The file's mark is not shown beside the
    /// official one as if they were two facts.
    @Test("A mark read from a file is marked superseded once the official one is out")
    func superseded() {
        let file = update(.resultsPosted, exam: nil, minutesAgo: 600, source: .webeep,
                          lookup: ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
        let official = update(.gradePublished, minutesAgo: 60, value: "27")
        let items = FeedItem.items(from: [official, file])
        #expect(items.last?.isSuperseded == true)
        #expect(items.last?.detail == String(localized: "Voto confermato sui Servizi Online"))
        #expect(items.first?.isSuperseded == false)
    }

    @Test("An official mark for another course supersedes nothing")
    func otherCourse() {
        let file = update(.resultsPosted, exam: nil, minutesAgo: 600, source: .webeep,
                          lookup: ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
        let other = ExamUpdate(
            kind: .gradePublished, examID: 2, courseCode: "X9", courseName: "Chimica",
            detectedAt: now.addingTimeInterval(-3600), source: .exams, evidence: "test",
            wasEnrolled: true, examDate: nil)
        #expect(FeedItem.items(from: [other, file]).last?.isSuperseded == false)
    }

    @Test("An official mark seen before the file also supersedes it")
    func officialFirst() {
        let official = update(.gradePublished, minutesAgo: 600, value: "27")
        let file = update(.resultsPosted, exam: nil, minutesAgo: 60, source: .webeep,
                          lookup: ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
        #expect(FeedItem.items(from: [file, official]).first?.isSuperseded == true)
    }

    @Test("An official mark of another sitting of the course does not")
    func otherSitting() {
        var file = update(.resultsPosted, exam: nil, minutesAgo: 600, source: .webeep,
                          lookup: ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
        file = ExamUpdate(kind: .resultsPosted, examID: nil, courseCode: "F1", courseName: "Fisica",
                          detectedAt: file.detectedAt, source: .webeep, evidence: "t", newValue: "Esiti.pdf",
                          wasEnrolled: true, examDate: now.addingTimeInterval(-5 * 86400))
        file.lookup = ResultsLookup(looksLikeResults: true, found: true, grade: "27")
        let official = ExamUpdate(kind: .gradePublished, examID: 3, courseCode: "F1", courseName: "Fisica",
                                  detectedAt: now, source: .exams, evidence: "t", newValue: "18",
                                  wasEnrolled: true, examDate: now.addingTimeInterval(-40 * 86400))
        #expect(FeedItem.items(from: [official, file]).last?.isSuperseded == false)
    }

    /// One notification per fact: the official mark replaces "you are in the
    /// results" on the lock screen.
    @Test("An official mark makes the course's delivered results notifications obsolete")
    func obsoleteNotifications() {
        let official = update(.gradePublished, minutesAgo: 1, value: "27")
        let delivered = ["update-resultsPosted|F1|Esiti.pdf@10@1", "update-resultsPosted|X9|Esiti.pdf@1@1",
                         "update-roomChanged|1|B.3.2"]
        #expect(ExamUpdatePolicy.obsoleteNotificationIDs(for: [official], delivered: delivered)
                    == ["update-resultsPosted|F1|Esiti.pdf@10@1"])
    }
}
