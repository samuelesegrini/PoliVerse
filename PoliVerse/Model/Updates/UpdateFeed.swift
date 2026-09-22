import Foundation
import Observation
import OSLog

/// Everything the app has noticed changing, for the signed-in student.
///
/// Two services feed it — ``CareerModel`` with the sittings and the libretto,
/// ``WeBeepModel`` with the course pages — and both go through here because they share
/// one ``ExamUpdateLog``: one file per matricola, one daily budget, one evening summary.
/// Written separately, each would overwrite the other's readings and the budget would
/// count half the pushes.
///
/// Every `record` method performs the same four steps — read the log, compare, decide
/// with ``ExamUpdatePolicy``, write back — and none of them awaits between reading and
/// writing, so two records cannot interleave on the main actor.
@Observable
final class UpdateFeed {
    /// The recorded updates for the account on screen, newest first.
    private(set) var updates: [ExamUpdate] = []
    /// WeBeep assignment deadlines still ahead, soonest first.
    private(set) var deadlines: [AssignmentDeadline] = []
    /// Handed whatever a record found for the first time, with its delivery already decided.
    /// ``NotificationModel/deliver(_:)`` is what the app passes.
    @ObservationIgnored private let onNewUpdates: (@MainActor ([ExamUpdate]) async -> Void)?
    /// The sittings currently known, so a WeBeep file can be weighed against the student's
    /// own exams.
    ///
    /// Assigned after construction rather than injected, because the dependency is a real
    /// cycle: ``CareerModel`` is built with the feed, so the feed cannot be built with the
    /// career. A closure resolved when it is read asks whoever holds the sittings at the
    /// moment the question arises.
    @ObservationIgnored var sittings: @MainActor () -> [ExamSession] = { [] }

    /// Where the per-account log is stored.
    private let offline: OfflineStore
    /// The matricola whose feed is on screen, from ``show(account:)``. `nil` under sample
    /// data and when signed out.
    private var account: String?
    /// Diagnostic log for this type, under the `updates` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "updates")

    /// The moment decisions are taken at.
    ///
    /// Quiet hours and the daily budget depend on it, so tests fix it rather than depending
    /// on when they run.
    private let clock: @Sendable () -> Date

    /// Creates the feed. Nothing is read until ``show(account:)``.
    ///
    /// - Parameters:
    ///   - offline: Where the per-account log is stored.
    ///   - clock: The moment decisions are taken at.
    ///   - onNewUpdates: Handed whatever a record found for the first time.
    init(offline: OfflineStore = .shared, clock: @escaping @Sendable () -> Date = { .now },
         onNewUpdates: (@MainActor ([ExamUpdate]) async -> Void)? = nil) {
        self.onNewUpdates = onNewUpdates
        self.offline = offline
        self.clock = clock
    }

    /// The last fortnight's updates: what changed since the student last looked, which is
    /// the reason most visits happen.
    var recent: [ExamUpdate] {
        updates.filter { $0.detectedAt > clock().addingTimeInterval(-14 * 86400) }
    }

    /// When the student last opened the full feed, for this account. `nil` when they never
    /// have.
    private(set) var seenAt: Date?

    /// How many facts in the last fortnight the student has not seen — counted as facts
    /// rather than sightings, so a mark and its refusal window count once.
    var unreadCount: Int { FeedItem.unreadCount(FeedItem.items(from: recent), seenAt: seenAt) }

    /// Records that the student has opened the full feed, in memory and in the log.
    func markSeen() {
        seenAt = clock()
        guard let account else { return }
        var log = load(account) ?? ExamUpdateLog()
        log.seenAt = seenAt
        offline.save(log, as: ExamUpdateLog.name, account: account)
    }

    /// Puts one account's feed on screen, reading it from the log.
    ///
    /// Signing out or switching career must not leave the previous student's feed on screen.
    /// Returns immediately when the account is already the one shown.
    ///
    /// - Parameter account: The matricola to show, or `nil` for signed out.
    func show(account: String?) {
        guard account != self.account else { return }
        self.account = account
        let log = load(account)
        seenAt = log?.seenAt
        updates = log?.updates ?? []
        deadlines = Self.upcoming(log, now: clock())
    }

    /// Puts sample data on screen. Nothing is read or written.
    ///
    /// - Parameters:
    ///   - sample: The updates to show.
    ///   - upcoming: The deadlines to show.
    func showSample(_ sample: [ExamUpdate], deadlines upcoming: [AssignmentDeadline] = []) {
        account = nil
        updates = sample
        deadlines = upcoming
        seenAt = nil
    }

    /// Compares a career load against the previous reading and records what changed.
    ///
    /// Does nothing when both requests failed.
    ///
    /// - Parameters:
    ///   - sessions: The sittings, or `nil` when that request failed.
    ///   - libretto: The libretto, or `nil` when that request failed.
    ///   - account: Whose data this is. A record for anyone but the account on screen is
    ///     stored but not surfaced.
    func recordExams(sessions: [ExamSession]?, libretto: [LibrettoExam]?, account: String) async {
        guard sessions != nil || libretto != nil else { return }
        await record(account: account) { log, now in
            let detected = ExamChangeDetector.detect(
                previous: log.state, sessions: sessions, libretto: libretto, now: now)
            log.state = detected.state
            return detected.updates
        }
    }

    /// Compares a WeBeep course listing against the previous reading and records what
    /// changed.
    ///
    /// When an inspector is supplied, a dry run against the log as it stands identifies the
    /// new results files, and each is read before the log is touched — a record must not
    /// await between reading and writing the log. What the file turns out to hold can then
    /// reclassify the update: a solutions file holding a table of marks becomes results, and
    /// a results file with no table becomes a notice.
    ///
    /// - Parameters:
    ///   - course: The course being read.
    ///   - sections: The course page's contents.
    ///   - account: Whose data this is.
    ///   - inspect: Reads a new results file for the student's own line, when they allowed
    ///     it. `nil` downloads nothing.
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

    /// Compares a course's announcements forum against the previous reading and records the
    /// new posts.
    ///
    /// Kept under its own key beside the course's files.
    ///
    /// - Parameters:
    ///   - course: The course being read.
    ///   - posts: The forum's discussions.
    ///   - account: Whose data this is.
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

    /// Records a course's new assignments and moved deadlines, and the deadlines still
    /// ahead.
    ///
    /// The deadlines are replaced per course, so an assignment the lecturer removed stops
    /// being reminded about.
    ///
    /// - Parameters:
    ///   - course: The course being read.
    ///   - assignments: The course's assignments.
    ///   - account: Whose data this is.
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

    /// Every deadline in the log that is still ahead, soonest first.
    ///
    /// - Parameters:
    ///   - log: The account's log, or `nil`.
    ///   - now: The moment to measure against.
    /// - Returns: The deadlines.
    private static func upcoming(_ log: ExamUpdateLog?, now: Date) -> [AssignmentDeadline] {
        (log?.deadlines ?? [:]).values.flatMap { $0 }.filter { $0.due > now }.sorted { $0.due < $1.due }
    }

    /// The four steps every record performs: read the log, compare, decide, write back.
    ///
    /// A pass that outlived a sign-out or a career switch still writes to its own account's
    /// log, but surfaces nothing and notifies nobody — another student's news must not
    /// reach the screen.
    ///
    /// - Parameters:
    ///   - account: Whose data this is.
    ///   - detect: Compares against the log, updating its readings in place, and returns
    ///     what it found.
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

    /// Reads one account's log.
    ///
    /// - Parameter account: The matricola, or `nil`.
    /// - Returns: The log, or `nil` when there is none.
    private func load(_ account: String?) -> ExamUpdateLog? {
        offline.load(ExamUpdateLog.self, as: ExamUpdateLog.name, account: account)?.value
    }

    /// The student's sittings of a course around now: the last one taken within
    /// ``ExamUpdatePolicy/resultsWindow``, and the next one enrolled in within
    /// ``ExamUpdatePolicy/noticeHorizon``.
    ///
    /// Only sittings the student enrolled in or has a mark for are considered.
    ///
    /// - Parameters:
    ///   - course: The course being read.
    ///   - sittings: Every sitting known.
    ///   - now: The moment to measure from.
    /// - Returns: The context a WeBeep finding is weighed against.
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
