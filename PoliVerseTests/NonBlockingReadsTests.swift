import Foundation
import Testing
@testable import PoliVerse

/// The second pass on main-thread work, after WWDC26's *Profile, fix, and
/// verify*: offline reads that no longer block the caller, and derived values
/// that views used to rebuild on every body pass. Each change keeps a promise
/// the blocking or recomputing code kept by construction.
@Suite("Non-blocking reads")
struct NonBlockingReadsTests {
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("nonblocking-\(UUID().uuidString)", isDirectory: true))
    }

    // MARK: OfflineStore.loaded

    @Test("An asynchronous read sees the saves queued before it")
    func loadedWaitsForWrites() async {
        let store = store()
        store.save(Payload(value: "first"), as: "x", account: "111")
        store.save(Payload(value: "second"), as: "x", account: "111")
        let entry = await store.loaded(Payload.self, as: "x", account: "111")
        #expect(entry?.value == Payload(value: "second"))
    }

    @Test("An asynchronous read refuses an anonymous account, like the blocking one")
    func loadedRefusesAnonymous() async {
        let store = store()
        #expect(await store.loaded(Payload.self, as: "x", account: nil) == nil)
        #expect(await store.loaded(Payload.self, as: "x", account: "") == nil)
    }

    // MARK: CachedSlot, claimed and finished

    @Test("A claimed restore adopts what it read")
    func claimAdopts() async {
        let store = store()
        store.save(Payload(value: "cached"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        let claim = slot.claimRestore(for: "111")
        #expect(claim != nil)
        let entry = await claim?.read()
        #expect(slot.finish(claim!, with: entry)?.value == "cached")
        #expect(slot.age != nil)
    }

    /// The race the split exists to handle: a fetch lands while the file is
    /// still being read, and the older disk copy must not replace it.
    @Test("A restore overtaken by a save is dropped")
    func claimLosesToSave() async {
        let store = store()
        store.save(Payload(value: "old"), as: "x", account: "111")
        var slot = CachedSlot<Payload>(name: "x", store: store)

        let claim = slot.claimRestore(for: "111")!
        slot.save(Payload(value: "fresh"), for: "111")
        let entry = await claim.read()
        #expect(slot.finish(claim, with: entry) == nil)
        #expect(slot.age == 0)
    }

    @Test("An account already restored is not claimed again")
    func claimOnce() {
        var slot = CachedSlot<Payload>(name: "x", store: store())
        #expect(slot.claimRestore(for: nil) == nil)
        #expect(slot.claimRestore(for: "111") != nil)
        #expect(slot.claimRestore(for: "111") == nil)
        #expect(slot.claimRestore(for: "222") != nil)
    }

    // MARK: Agenda, indexed by title

    @Test("Events are grouped by lowercased title and sorted within it")
    func indexesByTitle() {
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            AgendaEvent(id: 2, title: "Analisi 1", start: morning.addingTimeInterval(86400), end: morning.addingTimeInterval(90000), kind: .lecture),
            AgendaEvent(id: 1, title: "ANALISI 1", start: morning, end: morning.addingTimeInterval(3600), kind: .lecture),
            AgendaEvent(id: 3, title: "Fisica", start: morning, end: morning.addingTimeInterval(3600), kind: .exam),
        ]

        let index = AgendaModel.titleIndex(events)
        #expect(index["analisi 1"]?.map(\.id) == [1, 2])
        #expect(index["fisica"]?.map(\.id) == [3])
        #expect(index.count == 2)
    }

    /// The shell reads today's slice so that paging the calendar, which
    /// replaces the agenda week after week, does not redraw it each time.
    @Test("Today's slice matches the day index, and a far load changes it once at most")
    @MainActor
    func todaySlice() async {
        let agenda = AgendaModel(account: StubAccount(matricola: "111", isSample: true, http: FixtureHTTP([:])))
        await agenda.load(around: .now)
        #expect(agenda.eventsToday(now: .now) == agenda.events(on: .now))

        await agenda.ensureLoaded(covering: .now.addingTimeInterval(120 * 86400))
        let settled = agenda.today
        await agenda.ensureLoaded(covering: .now.addingTimeInterval(240 * 86400))
        #expect(agenda.today == settled)
    }

    // MARK: Teaching codes, without a regular expression

    @Test("Six ASCII digits are a teaching code, and nothing else is")
    func teachingCodes() {
        #expect(Course.isTeachingCode("054321"))
        #expect(!Course.isTeachingCode("05432"))
        #expect(!Course.isTeachingCode("0543210"))
        #expect(!Course.isTeachingCode("05432A"))
        #expect(!Course.isTeachingCode("０５４３２１"))
        #expect(!Course.isTeachingCode(""))
    }

    // MARK: TodayStyle, decoded once per string

    @Test("A stored look decodes the same whether or not it was decoded last")
    func lookDecodes() {
        var bold = TodayStyle()
        bold.showsGreeting = !bold.showsGreeting
        let plain = TodayStyle()

        #expect(TodayStyle(rawValue: bold.rawValue) == bold)
        #expect(TodayStyle(rawValue: bold.rawValue) == bold)
        #expect(TodayStyle(rawValue: plain.rawValue) == plain)
        #expect(TodayStyle(rawValue: "not json") == nil)
    }

    // MARK: UpdateFeed, rows kept until the log changes

    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func update(_ kind: ExamUpdate.Kind, exam: Int, minutesAgo: Double) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: exam, courseCode: "F1", courseName: "Fisica",
                   detectedAt: now.addingTimeInterval(-minutesAgo * 60), source: .exams,
                   evidence: "test", newValue: "\(exam)", wasEnrolled: true, examDate: nil)
    }

    @Test("Cached feed rows follow a change of the log")
    @MainActor
    func feedRowsFollowLog() {
        let fixed = now
        let feed = UpdateFeed(offline: store(), clock: { fixed })

        feed.showSample([update(.roomChanged, exam: 1, minutesAgo: 5)])
        #expect(feed.items.map(\.update.examID) == [1])
        #expect(feed.recentItems.count == 1)
        #expect(feed.unreadCount == 1)

        feed.showSample([update(.roomChanged, exam: 2, minutesAgo: 5),
                         update(.dateChanged, exam: 3, minutesAgo: 20 * 24 * 60)])
        #expect(feed.items.map(\.update.examID) == [2, 3])
        // The second is older than the fortnight.
        #expect(feed.recentItems.map(\.update.examID) == [2])
    }

    /// Marking the feed seen used to read the log back from disk first; it now
    /// reads the copy held for the shown account, which must be the same log.
    @Test("Marking seen twice keeps what the log already held")
    @MainActor
    func markSeenKeepsLog() async {
        let offline = store()
        let fixed = now
        let feed = UpdateFeed(offline: offline, clock: { fixed })
        feed.show(account: "1")
        await feed.recordExams(sessions: [], libretto: [], account: "1")
        feed.markSeen()
        feed.markSeen()

        let reopened = UpdateFeed(offline: offline, clock: { fixed })
        reopened.show(account: "1")
        #expect(reopened.seenAt == fixed)
        #expect(reopened.updates == feed.updates)
    }
}
