import Foundation
import Testing
@testable import PoliVerse

/// Which exam updates reach the lock screen, and which wait in the app.
///
/// Every update is true, and most are not worth an interruption. A published
/// mark is; a sitting appearing three months out is not. The policy is what
/// keeps the app's notifications from being switched off in the first week.
@Suite("Exam update policy")
struct ExamUpdatePolicyTests {
    /// 2026-02-25 10:00 in Rome.
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private var preferences: NotificationPreferences { NotificationPreferences() }

    private func update(
        _ kind: ExamUpdate.Kind, exam: Int? = 1, course: String = "F1",
        enrolled: Bool = true, inDays days: Double = 10, at detected: Date? = nil,
        delivery: ExamUpdate.Delivery = .inApp, value: String? = nil
    ) -> ExamUpdate {
        ExamUpdate(
            kind: kind, examID: exam, courseCode: course, courseName: "Fisica",
            detectedAt: detected ?? now, source: .exams, evidence: "test",
            newValue: value, wasEnrolled: enrolled,
            examDate: now.addingTimeInterval(days * 86400), delivery: delivery)
    }

    private func decide(_ updates: [ExamUpdate], history: [ExamUpdate] = [],
                        preferences: NotificationPreferences? = nil,
                        at time: Date? = nil) -> [ExamUpdate.Delivery] {
        ExamUpdatePolicy.decide(updates, history: history,
                                preferences: preferences ?? self.preferences,
                                now: time ?? now).map(\.delivery)
    }

    @Test("A published mark is urgent")
    func grade() {
        #expect(decide([update(.gradePublished)]) == [.urgent])
    }

    /// A mark nearly always arrives already refusable: one notification, not two.
    @Test("A refusal window opening with its mark is folded into the mark")
    func refusalFolded() {
        #expect(decide([update(.gradePublished), update(.refusalOpened)]) == [.urgent, .inApp])
        #expect(decide([update(.refusalOpened)]) == [.urgent])
    }

    @Test("A room matters by how soon the student sits the exam")
    func roomUrgency() {
        #expect(decide([update(.roomPublished, inDays: 1)]) == [.urgent])
        #expect(decide([update(.roomChanged, inDays: 5)]) == [.priority])
        #expect(decide([update(.roomPublished, inDays: 20)]) == [.inApp])
        #expect(decide([update(.roomPublished, enrolled: false, inDays: 1)]) == [.inApp])
        // Edited upstream after the sitting was held.
        #expect(decide([update(.roomChanged, inDays: -1)]) == [.inApp])
    }

    @Test("A moved or withdrawn sitting is urgent only for those enrolled")
    func moved() {
        #expect(decide([update(.dateChanged), update(.withdrawn, exam: 2)]) == [.urgent, .urgent])
        #expect(decide([update(.dateChanged, enrolled: false)]) == [.inApp])
    }

    @Test("Housekeeping stays in the app; openings wait for the evening")
    func quietKinds() {
        #expect(decide([update(.discovered), update(.enrolled, exam: 2),
                        update(.unenrolled, exam: 3)]) == [.inApp, .inApp, .inApp])
        #expect(decide([update(.enrolmentOpened)]) == [.digest])
        #expect(decide([update(.correctionsAvailable)]) == [.push])
    }

    /// The libretto recording a mark the student was already told about is
    /// the same fact twice.
    @Test("A recorded grade already announced as published is not announced again")
    func gradeRecordedOnce() {
        let recorded = update(.gradeRecorded, exam: nil, course: "F1")
        #expect(decide([recorded]) == [.digest])
        #expect(decide([recorded], history: [update(.gradePublished, delivery: .urgent)]) == [.inApp])
        #expect(decide([update(.gradePublished), recorded]) == [.urgent, .inApp])
    }

    @Test("Turning exam updates off keeps everything in the app")
    func optedOut() {
        var off = preferences
        off.examUpdates = false
        #expect(decide([update(.gradePublished)], preferences: off) == [.inApp])
    }

    @Test("At night only what is urgent goes out; the rest waits for the morning")
    func quietHours() {
        let night = PoliMiDate.time(23, 30, on: now)
        #expect(decide([update(.roomChanged, inDays: 5, at: night)], at: night) == [.morning])
        #expect(decide([update(.gradePublished, at: night)], at: night) == [.urgent])
    }

    /// Only ordinary pushes are rationed; an Alta update never waits for an
    /// allowance.
    @Test("Past the daily budget, ordinary pushes wait for the evening")
    func budget() {
        let earlier = (0..<3).map {
            update(.roomChanged, exam: 10 + $0, enrolled: false, at: now.addingTimeInterval(-7200), delivery: .push)
        }
        #expect(ExamUpdatePolicy.budgeted(.push, course: "F9", history: earlier, now: now) == .digest)
        #expect(decide([update(.roomChanged, inDays: 5)], history: earlier) == [.priority])
        #expect(decide([update(.gradePublished)], history: earlier) == [.urgent])
        // Yesterday's do not count against today.
        let yesterday = earlier.map {
            update(.roomChanged, exam: $0.examID, at: now.addingTimeInterval(-86400), delivery: .push)
        }
        #expect(ExamUpdatePolicy.budgeted(.push, course: "F9", history: yesterday, now: now) == .push)
    }

    @Test("At most one ordinary push per course an hour")
    func perCourse() {
        let recent = [update(.roomChanged, exam: 5, course: "F1", at: now.addingTimeInterval(-600), delivery: .push)]
        #expect(ExamUpdatePolicy.budgeted(.push, course: "F1", history: recent, now: now) == .digest)
        #expect(ExamUpdatePolicy.budgeted(.push, course: "F2", history: recent, now: now) == .push)
    }

    // MARK: - Notifications

    @Test("Each pushed update becomes one notification, grouped by sitting")
    func immediate() {
        let decided = [update(.gradePublished, delivery: .urgent, value: "27"),
                       update(.discovered, exam: 2, delivery: .inApp)]
        let planned = ExamUpdatePolicy.notifications(for: decided, now: now)
        #expect(planned.count == 1)
        #expect(planned[0].id == "update-\(decided[0].id)")
        #expect(planned[0].isTimeSensitive)
        #expect(planned[0].thread == "exam-1")
        #expect(planned[0].kind == .update)
    }

    /// A first refresh after a week away can find a lot at once.
    @Test("Many updates at once become a single summary")
    func burst() {
        let decided = (1...5).map { update(.roomChanged, exam: $0, delivery: $0 == 1 ? .urgent : .priority) }
        let planned = ExamUpdatePolicy.notifications(for: decided, now: now)
        #expect(planned.count == 1)
        #expect(planned[0].isTimeSensitive)
        #expect(planned[0].title.contains("5"))
    }

    @Test("Updates held for the evening are summarised at 18:00")
    func digest() {
        let morning = [update(.enrolmentOpened, delivery: .digest),
                       update(.enrolmentOpened, exam: 2, delivery: .digest),
                       update(.gradePublished, exam: 3, delivery: .urgent)]
        let digests = ExamUpdatePolicy.digests(from: morning, now: now)
        #expect(digests.count == 1)
        #expect(digests[0].fireDate == PoliMiDate.time(18, on: now))
        #expect(digests[0].body.contains("Fisica"))

        // Seen after 18:00: tomorrow's summary.
        let evening = PoliMiDate.time(20, on: now)
        let late = ExamUpdatePolicy.digests(
            from: [update(.enrolmentOpened, at: evening, delivery: .digest)], now: evening)
        #expect(late.first?.fireDate == PoliMiDate.time(18, on: now.addingTimeInterval(86400)))

        // Already delivered.
        #expect(ExamUpdatePolicy.digests(from: morning, now: PoliMiDate.time(19, on: now)).isEmpty)

        // Held overnight: out at 07:00, not at the next evening.
        let night = PoliMiDate.time(23, 30, on: now)
        let deferred = ExamUpdatePolicy.digests(
            from: [update(.roomChanged, at: night, delivery: .morning)], now: night)
        #expect(deferred.first?.fireDate == PoliMiDate.time(7, on: now.addingTimeInterval(86400)))
    }

    // MARK: - Log

    @Test("The log refuses a change it already holds and keeps newest first")
    func logDedup() {
        var log = ExamUpdateLog()
        let first = log.record([update(.roomPublished, value: "B.3.2")], state: ExamWatchState(), now: now)
        #expect(first.count == 1)
        let again = log.record([update(.roomPublished, at: now.addingTimeInterval(60), value: "B.3.2"),
                                update(.gradePublished, at: now.addingTimeInterval(60))],
                               state: ExamWatchState(), now: now)
        #expect(again.map(\.kind) == [.gradePublished])
        #expect(log.updates.map(\.kind) == [.gradePublished, .roomPublished])
    }

    /// A room can go A→B→A→B; the second A→B is news, not a duplicate.
    @Test("The same change seen again later is recorded again")
    func logRepeatsLater() {
        var log = ExamUpdateLog()
        log.record([update(.enrolled)], state: ExamWatchState(), now: now)
        let soon = now.addingTimeInterval(60)
        #expect(log.record([update(.enrolled, at: soon)], state: ExamWatchState(), now: soon).isEmpty)
        let later = now.addingTimeInterval(3 * 86400)
        #expect(log.record([update(.enrolled, at: later)], state: ExamWatchState(), now: later).count == 1)
        #expect(log.updates.count == 2)
    }

    @Test("The log forgets what is older than its retention")
    func logRetention() {
        var log = ExamUpdateLog()
        _ = log.record([update(.discovered, at: now.addingTimeInterval(-200 * 86400))],
                       state: ExamWatchState(), now: now.addingTimeInterval(-200 * 86400))
        _ = log.record([update(.discovered, exam: 2)], state: ExamWatchState(), now: now)
        #expect(log.updates.map(\.examID) == [2])
    }

    /// The snapshot is keyed by `c_appello`, an Int — a dictionary shape
    /// JSON has no native form for. What goes to disk must come back whole,
    /// or every launch would be a new baseline and nothing would ever change.
    @Test("The log survives a round trip through the offline store")
    func logPersists() throws {
        let store = OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let session = ExamSession(
            id: 42, courseName: "Fisica", courseCode: "F1", teacher: nil, date: now,
            room: "B.3.2", enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
            kind: nil, status: .enrolled)
        var log = ExamUpdateLog()
        let state = ExamChangeDetector.detect(previous: nil, sessions: [session], libretto: nil, now: now).state
        log.record([update(.roomPublished, value: "B.3.2")], state: state, now: now)

        store.save(log, as: ExamUpdateLog.name, account: "10123456")
        let restored = try #require(store.load(ExamUpdateLog.self, as: ExamUpdateLog.name, account: "10123456"))
        #expect(restored.value == log)
        #expect(restored.value.state?.exams?[42]?.room == "B.3.2")
    }

    /// Older builds stored preferences without this key; decoding must not
    /// throw away the student's other choices.
    @Test("Preferences stored before exam updates existed still decode")
    func legacyPreferences() throws {
        let legacy = #"{"lectures":false,"deadlines":true,"exams":true,"enrolments":false,"leadMinutes":30}"#
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data(legacy.utf8))
        #expect(decoded.lectures == false)
        #expect(decoded.leadMinutes == 30)
        #expect(decoded.examUpdates)
    }
}

/// WeBeep updates are read off file names: worth a push only when the
/// student's own sitting makes them likely to matter.
@Suite("Exam update policy · WeBeep")
struct MaterialUpdatePolicyTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func decide(_ kind: ExamUpdate.Kind, enrolled: Bool = true, examInDays days: Double?,
                        confidence: ExamUpdate.Confidence = .high, replaced: Bool = false) -> ExamUpdate.Delivery? {
        let update = ExamUpdate(
            kind: kind, examID: nil, courseCode: "097785", courseName: "Basi di Dati",
            detectedAt: now, source: .webeep, confidence: confidence, evidence: "test",
            oldValue: replaced ? "10@1" : nil, newValue: "Esiti.pdf", wasEnrolled: enrolled,
            examDate: days.map { now.addingTimeInterval($0 * 86400) })
        return ExamUpdatePolicy.decide([update], history: [], preferences: NotificationPreferences(), now: now)
            .first?.delivery
    }

    @Test("A results file pushes only after the student's own sitting")
    func results() {
        #expect(decide(.resultsPosted, examInDays: -4) == .push)
        #expect(decide(.resultsPosted, enrolled: false, examInDays: -4) == .digest)
        #expect(decide(.resultsPosted, examInDays: 10) == .digest)
        #expect(decide(.resultsPosted, examInDays: -90) == .digest)
        #expect(decide(.resultsPosted, examInDays: nil) == .digest)
        // An ambiguous name, or a correction of a file already announced.
        #expect(decide(.resultsPosted, examInDays: -4, confidence: .probable) == .digest)
        #expect(decide(.resultsPosted, examInDays: -4, replaced: true) == .digest)
    }

    /// §21: from WeBeep, only results may push.
    @Test("Notices and solutions wait for the evening, and only with a sitting in play")
    func quiet() {
        #expect(decide(.examNoticePosted, examInDays: 5) == .digest)
        #expect(decide(.examNoticePosted, enrolled: false, examInDays: nil) == .inApp)
        #expect(decide(.solutionsPosted, examInDays: -2) == .digest)
        #expect(decide(.solutionsPosted, enrolled: false, examInDays: nil) == .inApp)
        #expect(decide(.materialAdded, enrolled: false, examInDays: nil) == .inApp)
    }
}

@Suite("Exam update policy · read results files")
struct ResultsLookupPolicyTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func decide(_ lookup: ResultsLookup, history: [ExamUpdate] = []) -> ExamUpdate.Delivery? {
        var update = ExamUpdate(
            kind: .resultsPosted, examID: nil, courseCode: "097785", courseName: "Basi di Dati",
            detectedAt: now, source: .webeep, confidence: .probable, evidence: "test",
            newValue: "Esiti.pdf", wasEnrolled: false, examDate: nil)
        update.lookup = lookup
        return ExamUpdatePolicy.decide([update], history: history, preferences: NotificationPreferences(), now: now)
            .first?.delivery
    }

    @Test("Being in the file pushes, whatever the name or context said")
    func found() {
        #expect(decide(ResultsLookup(looksLikeResults: true, found: true, grade: "27")) == .push)
    }

    @Test("Not in it waits for the evening; not a results table stays in the app")
    func notFound() {
        #expect(decide(ResultsLookup(looksLikeResults: true, found: false, grade: nil)) == .digest)
        #expect(decide(ResultsLookup(looksLikeResults: false, found: false, grade: nil)) == .inApp)
    }

    /// The exam services already said it: the file is the same fact again.
    @Test("A mark already published officially is not announced again from the file")
    func alreadyOfficial() {
        let official = ExamUpdate(
            kind: .gradePublished, examID: 1, courseCode: "097785", courseName: "Basi di Dati",
            detectedAt: now.addingTimeInterval(-3600), source: .exams, evidence: "test",
            wasEnrolled: true, examDate: nil, delivery: .urgent)
        #expect(decide(ResultsLookup(looksLikeResults: true, found: true, grade: "27"), history: [official]) == .inApp)
    }
}

@Suite("Exam update policy · announcements")
struct AnnouncementPolicyTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    @Test("A post about a sitting in play pushes; any other waits for the evening")
    func announcements() {
        func decide(examInDays days: Double?) -> ExamUpdate.Delivery? {
            let update = ExamUpdate(
                kind: .announcementPosted, examID: nil, courseCode: "097785", courseName: "Basi di Dati",
                detectedAt: now, source: .webeep, evidence: "test", newValue: "Aule",
                wasEnrolled: days != nil, examDate: days.map { now.addingTimeInterval($0 * 86400) })
            return ExamUpdatePolicy.decide([update], history: [], preferences: NotificationPreferences(), now: now)
                .first?.delivery
        }
        #expect(decide(examInDays: 4) == .push)
        #expect(decide(examInDays: nil) == .digest)
    }
}
