import Foundation
import Testing
@testable import PoliVerse

/// The one log both the career and WeBeep write to.
@MainActor
@Suite("Update feed")
struct UpdateFeedTests {
    /// 10:00 in Rome: outside quiet hours whenever the suite runs.
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    private func sitting(room: String? = nil, days: Double = 10, code: String = "097785") -> ExamSession {
        ExamSession(
            id: 1, courseName: "Basi di Dati", courseCode: code, teacher: nil,
            date: now.addingTimeInterval(days * 86400), room: room,
            enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
            kind: nil, status: .enrolled)
    }

    private let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")

    private func listing(_ names: [String]) -> [MoodleSection] {
        [MoodleSection(id: 1, name: "Esami", modules: names.enumerated().map { index, name in
            MoodleModule(id: index + 1, name: name, modname: "resource", contents: [
                MoodleContent(type: "file", filename: name, filesize: 10, fileurl: nil,
                              timemodified: 1, mimetype: "application/pdf"),
            ])
        })]
    }

    @Test("A change is recorded, persisted and handed on once")
    func recordsExams() async {
        let offline = store()
        let feed = UpdateFeed(offline: offline, clock: { [now] in now })
        feed.show(account: "10123456")
        var delivered: [ExamUpdate.Kind] = []
        feed.onNewUpdates = { delivered += $0.map(\.kind) }

        await feed.recordExams(sessions: [sitting()], libretto: nil, account: "10123456")
        await feed.recordExams(sessions: [sitting(room: "B.3.2")], libretto: nil, account: "10123456")
        await feed.recordExams(sessions: [sitting(room: "B.3.2")], libretto: nil, account: "10123456")

        #expect(delivered == [.roomPublished])
        #expect(feed.updates.map(\.kind) == [.roomPublished])
        let reopened = UpdateFeed(offline: offline, clock: { [now] in now })
        reopened.show(account: "10123456")
        #expect(reopened.updates.map(\.kind) == [.roomPublished])
    }

    /// Written separately, each source would overwrite the other's snapshot
    /// and every load would be a new baseline.
    @Test("Exams and WeBeep share the log without erasing each other's snapshot")
    func sharedLog() async {
        let feed = UpdateFeed(offline: store(), clock: { [now] in now })
        feed.show(account: "1")
        feed.sittings = { [sitting(days: -3)] }
        await feed.recordExams(sessions: [sitting(days: -3)], libretto: nil, account: "1")
        await feed.recordMaterials(course: course, sections: listing(["Lezione 01.pdf"]), account: "1")
        await feed.recordExams(sessions: [sitting(room: "B.3.2", days: -3)], libretto: nil, account: "1")
        await feed.recordMaterials(course: course, sections: listing(["Lezione 01.pdf", "Esiti.pdf"]), account: "1")

        #expect(feed.updates.map(\.kind) == [.resultsPosted, .roomPublished])
        // Just after the student's own sitting: worth a push.
        #expect(feed.updates.first?.delivery == .push)
    }

    @Test("Switching account shows that account's feed, and signing out shows none")
    func accounts() async {
        let offline = store()
        let feed = UpdateFeed(offline: offline, clock: { [now] in now })
        feed.show(account: "A")
        await feed.recordExams(sessions: [sitting()], libretto: nil, account: "A")
        await feed.recordExams(sessions: [sitting(room: "B.3.2")], libretto: nil, account: "A")
        #expect(!feed.updates.isEmpty)
        feed.show(account: "B")
        #expect(feed.updates.isEmpty)
        feed.show(account: "A")
        #expect(!feed.updates.isEmpty)
        feed.show(account: nil)
        #expect(feed.updates.isEmpty)
    }

    /// A pass that outlived a sign-out must not put the old account back.
    @Test("A record for an account not on screen is kept but not shown or delivered")
    func notShown() async {
        let feed = UpdateFeed(offline: store(), clock: { [now] in now })
        var delivered = 0
        feed.onNewUpdates = { delivered += $0.count }
        feed.show(account: nil)
        await feed.recordExams(sessions: [sitting()], libretto: nil, account: "A")
        await feed.recordExams(sessions: [sitting(room: "B.3.2")], libretto: nil, account: "A")
        #expect(feed.updates.isEmpty)
        #expect(delivered == 0)
        feed.show(account: "A")
        #expect(feed.updates.map(\.kind) == [.roomPublished])
    }

    @Test("A course page's news is weighed against the student's nearest sitting")
    func context() {
        let upcoming = sitting(days: 5)
        let past = sitting(days: -3)
        #expect(UpdateFeed.context(for: course, among: [upcoming, past], now: now)
                    == MaterialContext(lastSat: past.date, next: upcoming.date))
        #expect(UpdateFeed.context(for: course, among: [sitting(days: 40)], now: now) == .none)
        #expect(UpdateFeed.context(for: course, among: [sitting(days: 5, code: "999")], now: now)
                    .next != nil)   // matched by name
        let other = MaterialCourse(moodleID: 9, code: "111111", name: "Chimica")
        #expect(UpdateFeed.context(for: other, among: [upcoming], now: now) == .none)
    }
}

@MainActor
@Suite("Update feed · results files")
struct UpdateFeedResultsTests {
    nonisolated private static let noon = PoliMiDate.time(12, on: Date(timeIntervalSince1970: 1_772_000_000))
    private func listing(_ names: [String]) -> [MoodleSection] {
        [MoodleSection(id: 1, name: "Esami", modules: names.enumerated().map { index, name in
            MoodleModule(id: index + 1, name: name, modname: "resource", contents: [
                MoodleContent(type: "file", filename: name, filesize: 10,
                              fileurl: "https://webeep.polimi.it/f/\(index + 1)",
                              timemodified: 1, mimetype: "application/pdf"),
            ])
        })]
    }

    @Test("A new results file is read only when allowed, and only the lookup is kept")
    func inspected() async {
        let feed = UpdateFeed(offline: OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)), clock: { Self.noon })
        feed.show(account: "1")
        let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")
        var asked: [String] = []
        let inspect: @MainActor (ResultsFileRef) async -> ResultsLookup? = { file in
            asked.append(file.name)
            return ResultsLookup(looksLikeResults: true, found: true, grade: "27")
        }

        await feed.recordMaterials(course: course, sections: listing(["Lezione.pdf"]), account: "1", inspect: inspect)
        #expect(asked.isEmpty)   // baseline: nothing new, nothing read
        await feed.recordMaterials(course: course, sections: listing(["Lezione.pdf", "Esiti.pdf"]),
                                   account: "1", inspect: inspect)

        #expect(asked == ["Esiti.pdf"])
        let update = feed.updates.first
        #expect(update?.lookup == ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
        #expect(update?.delivery == .push)
        #expect(update?.title == String(localized: "Sei negli esiti"))
    }

    /// §10.3: the content decides when it disagrees with the name.
    @Test("A solutions file holding marks is results; a results file with no table is a notice")
    func contentDecides() async {
        let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")
        func run(_ name: String, _ lookup: ResultsLookup) async -> ExamUpdate? {
            let feed = UpdateFeed(offline: OfflineStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)), clock: { Self.noon })
            feed.show(account: "1")
            await feed.recordMaterials(course: course, sections: listing(["Lezione.pdf"]), account: "1")
            await feed.recordMaterials(course: course, sections: listing(["Lezione.pdf", name]), account: "1",
                                       inspect: { _ in lookup })
            return feed.updates.first
        }
        let marks = await run("Soluzioni appello.pdf", ResultsLookup(looksLikeResults: true, found: false, grade: nil))
        #expect(marks?.kind == .resultsPosted)
        let notice = await run("Risultati orale.pdf", ResultsLookup(looksLikeResults: false, found: false, grade: nil))
        #expect(notice?.kind == .examNoticePosted)
        let mention = await run("Esiti.pdf", ResultsLookup(looksLikeResults: false, found: true, grade: nil))
        #expect(mention?.kind == .resultsPosted)
        #expect(mention?.delivery == .digest)   // found, but not in a table
    }
}
