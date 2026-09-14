import Foundation
import Observation
import OSLog

/// Everything the app has noticed changing, for the signed-in student.
///
/// Two services feed it — ``CareerService`` with exam sittings and the
/// libretto, ``WeBeepService`` with course pages — and both go through here
/// because they share one log: one file per matricola, one daily budget, one
/// evening summary. Written separately, each would overwrite the other's
/// snapshot and the budget would count half the pushes.
///
/// Every record is the same four steps: read the log, compare, decide with
/// ``ExamUpdatePolicy``, write back. None of them awaits, so two records can
/// never interleave on the main actor.
@Observable
final class UpdateFeed {
    /// Newest first.
    private(set) var updates: [ExamUpdate] = []
    /// WeBeep assignment deadlines still ahead, soonest first.
    private(set) var deadlines: [AssignmentDeadline] = []
    /// Handed what a record found for the first time, already decided.
    /// Wired to the notification service at launch.
    @ObservationIgnored var onNewUpdates: (@MainActor ([ExamUpdate]) async -> Void)?
    /// The sittings currently known, so a WeBeep file can be weighed against
    /// the student's own exams. Wired to ``CareerService`` at launch.
    @ObservationIgnored var sittings: @MainActor () -> [ExamSession] = { [] }

    private let offline: OfflineStore
    private var account: String?
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "updates")

    /// The time decisions are taken at. Quiet hours and the daily budget
    /// depend on it, so tests fix it rather than depend on when they run.
    private let clock: @Sendable () -> Date

    init(offline: OfflineStore = .shared, clock: @escaping @Sendable () -> Date = { .now }) {
        self.offline = offline
        self.clock = clock
    }

    /// The last fortnight: what changed since the student last looked, which
    /// is the reason most visits happen.
    var recent: [ExamUpdate] {
        updates.filter { $0.detectedAt > clock().addingTimeInterval(-14 * 86400) }
    }

    /// Shows this account's feed. Signing out, or switching career, must not
    /// leave the previous student's on screen.
    func show(account: String?) {
        guard account != self.account else { return }
        self.account = account
        let log = load(account)
        updates = log?.updates ?? []
        deadlines = Self.upcoming(log, now: clock())
    }

    /// Sample data, never written anywhere.
    func showSample(_ sample: [ExamUpdate]) {
        account = nil
        updates = sample
        deadlines = []
    }

    /// - Parameter account: whose data this is. Callers show it first; a
    ///   record for anyone else is kept but not surfaced.
    func recordExams(sessions: [ExamSession]?, libretto: [LibrettoExam]?, account: String) async {
        guard sessions != nil || libretto != nil else { return }
        await record(account: account) { log, now in
            let detected = ExamChangeDetector.detect(
                previous: log.state, sessions: sessions, libretto: libretto, now: now)
            log.state = detected.state
            return detected.updates
        }
    }

    /// - Parameter inspect: reads a new results file for the student's own
    ///   line, when they allowed it. Runs before the log is touched: it
    ///   awaits a download, and a record must never await between reading
    ///   and writing the log.
    func recordMaterials(
        course: MaterialCourse, sections: [MoodleSection], account: String,
        inspect: (@MainActor (ResultsFileRef) async -> ResultsLookup?)? = nil
    ) async {
        let context = Self.context(for: course, among: sittings(), now: clock())
        let items = MaterialItem.items(from: sections)
        let key = String(course.moodleID)

        var lookups: [String: ResultsLookup] = [:]
        if let inspect {
            // A dry run against the log as it is now, to learn which files
            // are new; the real record below compares again from scratch.
            let preview = MaterialChangeDetector.detect(
                previous: load(account)?.materials?[key], current: items,
                course: course, context: context, now: clock())
            for (id, file) in preview.files {
                lookups[id] = await inspect(file)
            }
        }

        await record(account: account) { log, now in
            let detected = MaterialChangeDetector.detect(
                previous: log.materials?[key], current: items,
                course: course, context: context, now: now)
            log.materials = (log.materials ?? [:]).merging([key: detected.snapshot]) { _, new in new }
            return detected.updates.map { update in
                guard let lookup = lookups[update.id] else { return update }
                switch update.kind {
                case .solutionsPosted where lookup.looksLikeResults:
                    return update.reclassified(as: .resultsPosted, lookup: lookup)
                case .solutionsPosted:
                    return update
                case .resultsPosted where !lookup.looksLikeResults && !lookup.found:
                    return update.reclassified(as: .examNoticePosted, lookup: nil)
                default:
                    var read = update
                    read.lookup = lookup
                    return read
                }
            }
        }
    }

    /// New posts in a course's announcements forum.
    func recordAnnouncements(course: MaterialCourse, posts: [MoodleDiscussion], account: String) async {
        let context = Self.context(for: course, among: sittings(), now: clock())
        await record(account: account) { log, now in
            // Beside the course's files, under their own key.
            let key = "forum-\(course.moodleID)"
            let detected = AnnouncementDetector.detect(
                previous: log.materials?[key], posts: posts, course: course, context: context, now: now)
            log.materials = (log.materials ?? [:]).merging([key: detected.snapshot]) { _, new in new }
            return detected.updates
        }
    }

    /// A course's assignments: new ones and moved deadlines as updates, and
    /// the deadlines ahead kept for the reminders — replaced per course, so an
    /// assignment the teacher removed stops being reminded.
    func recordAssignments(course: MaterialCourse, assignments: [MoodleAssignment], account: String) async {
        await record(account: account) { log, now in
            let key = AssignmentDetector.courseKey(course)
            let detected = AssignmentDetector.detect(
                previous: log.materials?[key], assignments: assignments, course: course, now: now)
            log.materials = (log.materials ?? [:]).merging([key: detected.snapshot]) { _, new in new }
            log.deadlines = (log.deadlines ?? [:]).merging([key: detected.deadlines]) { _, new in new }
            return detected.updates
        }
    }

    private static func upcoming(_ log: ExamUpdateLog?, now: Date) -> [AssignmentDeadline] {
        (log?.deadlines ?? [:]).values.flatMap { $0 }.filter { $0.due > now }.sorted { $0.due < $1.due }
    }

    private func record(
        account: String, detect: (inout ExamUpdateLog, Date) -> [ExamUpdate]
    ) async {
        let now = clock()
        var history = load(account) ?? ExamUpdateLog()
        let found = detect(&history, now)
        // Recorded for whoever it belongs to, but only the student on screen
        // sees it or is told: a pass that outlived a sign-out or a career
        // switch must not surface another account's news.
        let isShown = account == self.account
        let decided = ExamUpdatePolicy.decide(
            history.unseen(found), history: history.updates,
            preferences: .stored, now: now)
        let added = history.record(decided, state: history.state ?? ExamWatchState(), now: now)
        offline.save(history, as: ExamUpdateLog.name, account: account)
        guard isShown else { return }
        updates = history.updates
        deadlines = Self.upcoming(history, now: now)

        guard !added.isEmpty else { return }
        let kinds = added.map(\.kind.rawValue).joined(separator: ", ")
        log.notice("Updates: \(kinds, privacy: .public)")
        await onNewUpdates?(added)
    }

    private func load(_ account: String?) -> ExamUpdateLog? {
        offline.load(ExamUpdateLog.self, as: ExamUpdateLog.name, account: account)?.value
    }

    /// The student's sittings of a course around now: the last one taken
    /// within two months, and the next one enrolled in within a fortnight.
    static func context(for course: MaterialCourse, among sittings: [ExamSession], now: Date) -> MaterialContext {
        let dates = sittings.compactMap { sitting -> Date? in
            guard sitting.status == .enrolled || sitting.grade != nil,
                  sitting.isOf(courseCode: course.code, courseName: course.name)
            else { return nil }
            return sitting.date
        }
        return MaterialContext(
            lastSat: dates
                .filter { $0 < now && now.timeIntervalSince($0) <= ExamUpdatePolicy.resultsWindow }
                .max(),
            next: dates
                .filter { $0 >= now && $0.timeIntervalSince(now) <= ExamUpdatePolicy.noticeHorizon }
                .min())
    }
}
