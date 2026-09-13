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
    /// Handed what a record found for the first time, already decided.
    /// Wired to the notification service at launch.
    @ObservationIgnored var onNewUpdates: (@MainActor ([ExamUpdate]) async -> Void)?
    /// The sittings currently known, so a WeBeep file can be weighed against
    /// the student's own exams. Wired to ``CareerService`` at launch.
    @ObservationIgnored var sittings: @MainActor () -> [ExamSession] = { [] }

    private let offline: OfflineStore
    private var account: String?
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "updates")

    init(offline: OfflineStore = .shared) {
        self.offline = offline
    }

    /// The last fortnight: what changed since the student last looked, which
    /// is the reason most visits happen.
    var recent: [ExamUpdate] {
        updates.filter { $0.detectedAt > .now.addingTimeInterval(-14 * 86400) }
    }

    /// Shows this account's feed. Signing out, or switching career, must not
    /// leave the previous student's on screen.
    func show(account: String?) {
        guard account != self.account else { return }
        self.account = account
        updates = load(account)?.updates ?? []
    }

    /// Sample data, never written anywhere.
    func showSample(_ sample: [ExamUpdate]) {
        account = nil
        updates = sample
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

    func recordMaterials(course: MaterialCourse, sections: [MoodleSection], account: String) async {
        let context = Self.context(for: course, among: sittings(), now: .now)
        await record(account: account) { log, now in
            let key = String(course.moodleID)
            let detected = MaterialChangeDetector.detect(
                previous: log.materials?[key], current: MaterialItem.items(from: sections),
                course: course, context: context, now: now)
            log.materials = (log.materials ?? [:]).merging([key: detected.snapshot]) { _, new in new }
            return detected.updates
        }
    }

    private func record(
        account: String, detect: (inout ExamUpdateLog, Date) -> [ExamUpdate]
    ) async {
        let now = Date.now
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
