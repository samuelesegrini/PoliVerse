import Foundation
import Observation
import OSLog

/// The student's academic record, as the screens read it.
///
/// The six endpoints and their partial-failure rules are ``CareerSource``'s;
/// the window, the offline copy and the error text are ``Store``'s. What is
/// left here is what only this feature knows: what a load means for the update
/// feed and the widgets, saving a target average back to Servizi Online, and
/// the figures derived from the libretto.
@Observable
@MainActor
final class CareerModel {
    private let store: Store<CareerSource>
    private let account: any Account
    private let feed: UpdateFeed
    private let offline: OfflineStore
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "career")

    /// Where a change goes when it cannot be sent now.
    var pending: PendingChanges?

    /// A target the student set here but that has not reached Servizi Online
    /// yet. Newer than the fetched value, so it wins until the queue delivers.
    private var localTarget: Double?

    init(account: any Account, feed: UpdateFeed, offline: OfflineStore = .shared) {
        self.account = account
        self.feed = feed
        self.offline = offline
        self.store = Store(CareerSource(), account: account, offline: offline)
    }

    // MARK: - What the screens read

    private var payload: CareerSource.Payload { store.value ?? CareerSource.Payload() }

    var gradeBook: GradeBook { payload.gradeBook }
    var sessions: [ExamSession] { payload.sessions }
    var libretto: [LibrettoExam] { payload.libretto }
    var planHeader: StudyPlanHeader? { payload.planHeader }
    var officialTarget: Double? { localTarget ?? payload.officialTarget }
    /// The Politecnico accepted the login but refuses this account's profile
    /// for the exam services. Kept separate from an error because the two are
    /// genuinely different: the session is fine, a subset of services is not.
    var examServicesRefused: Bool { payload.servicesRefused }

    var isLoading: Bool { store.isLoading }
    var age: TimeInterval? { store.age }

    /// Nil when the services refused this profile: that is reported in its own
    /// words rather than as a failure the student could retry.
    var errorMessage: String? {
        examServicesRefused ? nil : store.errorMessage
    }

    /// The arithmetic over the libretto, which is a value type and testable on
    /// its own — see ``StudyPlan``.
    var studyPlan: StudyPlan { StudyPlan(exams: libretto) }
    /// The questions the screens ask of the sittings — see ``Sittings``.
    var sittings: Sittings { Sittings(sessions) }

    /// Passed exams, most recent first.
    ///
    /// Sourced from the libretto rather than from exam sittings: sittings
    /// disappear from `/v1/insegn` once there is nothing left to register for,
    /// so a student who has passed everything would see an empty list.
    var passedExams: [LibrettoExam] {
        studyPlan.passed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Teachings in the plan with no result yet.
    var pendingExams: [LibrettoExam] {
        studyPlan.pending.sorted { $0.name < $1.name }
    }

    var weightedMean: Double? { studyPlan.weightedMean }
    var lastGraded: LibrettoExam? { studyPlan.lastGraded }
    var meanDelta: Double? { studyPlan.meanDelta }

    var upcoming: [ExamSession] { sittings.upcoming() }
    var enrolled: [ExamSession] { sittings.enrolled() }

    func sitting(for update: ExamUpdate) -> ExamSession? { sittings.sitting(for: update) }

    /// The study plan another career last showed, read from its cache. The
    /// token is bound to one matricola, so this is the only way to see a
    /// second career's plan without switching to it.
    static func cachedLibretto(account: String, store: OfflineStore = .shared) -> [LibrettoExam]? {
        store.load(CareerSource.Payload.self, as: CareerSource.id, account: account)?
            .value.libretto
    }

    // MARK: - Loading

    func load(force: Bool = false) async {
        // Before the load, not after: signing out must clear the feed whether
        // or not anything is fetched.
        if account.isSample {
            feed.showSample(ExamUpdate.samples(), deadlines: AssignmentDeadline.samples())
        } else {
            feed.show(account: account.matricola)
        }

        await store.load(force: force)

        // Only on a load that actually got somewhere. What is held after a
        // failure is the cached record, and re-recording it would have the
        // feed reasoning about data it has already seen.
        guard !account.isSample, store.errorMessage == nil,
              let matricola = account.matricola else { return }
        await feed.recordExams(sessions: payload.sessions, libretto: payload.libretto,
                               account: matricola)
        saveWidgetSnapshot(for: matricola)
    }

    /// Writes the narrow view of the career that the widgets read.
    ///
    /// Separate from the store's offline copy, and deliberately so — a widget
    /// should not decode a student's whole exam record to show one number.
    private func saveWidgetSnapshot(for account: String) {
        let next = sittings.next()

        let snapshot = CareerSnapshot(
            mean: gradeBook.mean,
            earnedCFU: gradeBook.earnedCFU,
            plannedCFU: gradeBook.plannedCFU,
            examsGiven: gradeBook.examsGiven,
            examsPlanned: gradeBook.examsPlanned,
            nextExamName: next?.courseName,
            nextExamDate: next?.date)
        offline.save(snapshot, as: CareerSnapshot.cacheName, account: account)
        WidgetReloader.request([.career])
    }

    // MARK: - Changes the user makes

    /// Saves a target average back to Servizi Online.
    ///
    /// `PUT /mediaobiettivo/insertmediaobiettivo` with `{matricola, media}`,
    /// exactly as the official app sends it. A write to the real system, so it
    /// happens only when the user presses save — never from the slider.
    func saveTarget(_ media: Double) async -> Bool {
        guard let matricola = account.matricola else { return false }
        // Held locally either way: the figure the student chose is theirs, and
        // losing it because a tunnel arrived first would be rude.
        localTarget = media
        let body = try? JSONSerialization.data(
            withJSONObject: ["matricola": matricola, "media": media])
        do {
            _ = try await account.http.data(for: APIRequest(
                host: .libretto,
                path: "/mediaobiettivo/insertmediaobiettivo",
                method: "PUT",
                body: body))
            log.notice("Saved target average \(media, privacy: .public)")
            return true
        } catch {
            log.error("Could not save the target: \(error.localizedDescription)")
            pending?.record(.targetAverage(media))
            return false
        }
    }
}
