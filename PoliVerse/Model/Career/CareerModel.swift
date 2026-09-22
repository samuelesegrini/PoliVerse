import Foundation
import Observation
import OSLog

/// The student's academic record, as the screens read it.
///
/// The six endpoints and their partial-failure rules belong to ``CareerSource``, and
/// the load window, offline copy and error text to ``Store``. What is here is what
/// only this feature knows: what a load means for ``UpdateFeed`` and the widgets,
/// saving a target average back to Servizi Online, and the figures derived from the
/// libretto through ``StudyPlan`` and ``Sittings``.
@Observable
@MainActor
final class CareerModel {
    /// The loaded record, with its cache and load window.
    private let store: Store<CareerSource>
    /// Whose record is loaded, and the transport the target write goes through.
    private let account: any Account
    /// Told about every successful load, so it can notice what changed.
    private let feed: UpdateFeed
    /// Where the widgets' ``CareerSnapshot`` is written.
    private let offline: OfflineStore
    /// Diagnostic log for this type, under the `career` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "career")

    /// Where a target average goes when it cannot be sent now.
    private let pending: PendingChanges?

    /// A target the student set here that has not reached Servizi Online yet. Newer than
    /// the fetched value, so it wins until the queue delivers it.
    private var localTarget: Double?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - account: Whose record to load.
    ///   - feed: Told about every successful load.
    ///   - pending: Where an undeliverable target average is queued.
    ///   - offline: Where the record and the widget snapshot are stored.
    init(account: any Account, feed: UpdateFeed, pending: PendingChanges? = nil,
         offline: OfflineStore = .shared) {
        self.account = account
        self.feed = feed
        self.pending = pending
        self.offline = offline
        self.store = Store(CareerSource(), account: account, offline: offline)
    }

    // MARK: - What the screens read

    /// The loaded record, or an empty one before the first load.
    private var payload: CareerSource.Payload { store.value ?? CareerSource.Payload() }

    /// The aggregate figures.
    var gradeBook: GradeBook { payload.gradeBook }
    /// Every exam sitting known.
    var sessions: [ExamSession] { payload.sessions }
    /// The study plan with its results.
    var libretto: [LibrettoExam] { payload.libretto }
    /// The plan's header, where the endpoint answered.
    var planHeader: StudyPlanHeader? { payload.planHeader }
    /// The target average: the unsent local one if there is one, else the fetched value.
    var officialTarget: Double? { localTarget ?? payload.officialTarget }
    /// Whether the Politecnico accepted the sign-in but refuses this account's profile
    /// for the exam services. Kept apart from ``errorMessage``, since the session is fine
    /// and only a subset of services is not.
    var examServicesRefused: Bool { payload.servicesRefused }

    /// `true` while a load is in flight.
    var isLoading: Bool { store.isLoading }
    /// Seconds since the record was fetched, or `nil` if never.
    var age: TimeInterval? { store.age }

    /// The last load's error, or `nil` when it succeeded — and `nil` while
    /// ``examServicesRefused`` holds, since that is reported in its own words rather than
    /// as a failure the student could retry.
    var errorMessage: String? {
        examServicesRefused ? nil : store.errorMessage
    }

    /// The libretto's arithmetic. See ``StudyPlan``.
    var studyPlan: StudyPlan { StudyPlan(exams: libretto) }
    /// The sittings' questions. See ``Sittings``.
    var sittings: Sittings { Sittings(sessions) }

    /// Passed exams, most recent first.
    ///
    /// Taken from the libretto rather than from the sittings, which disappear from the
    /// exams endpoint once there is nothing left to register for — so a student who has
    /// passed everything would otherwise see an empty list.
    var passedExams: [LibrettoExam] {
        studyPlan.passed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Teachings in the plan with no result yet, by name.
    var pendingExams: [LibrettoExam] {
        studyPlan.pending.sorted { $0.name < $1.name }
    }

    /// The credit-weighted average of the recorded marks, or `nil` with no marks.
    var weightedMean: Double? { studyPlan.weightedMean }
    /// The most recently marked teaching, or `nil` with none.
    var lastGraded: LibrettoExam? { studyPlan.lastGraded }
    /// How far the last mark moved the average, or `nil` when it cannot be told.
    var meanDelta: Double? { studyPlan.meanDelta }

    /// Unmarked sittings still ahead, soonest first.
    var upcoming: [ExamSession] { sittings.upcoming() }
    /// Upcoming sittings the student is enrolled in.
    var enrolled: [ExamSession] { sittings.enrolled() }

    /// The sitting an update is about.
    ///
    /// - Parameter update: The update to resolve.
    /// - Returns: The sitting, or `nil` when it is no longer listed.
    func sitting(for update: ExamUpdate) -> ExamSession? { sittings.sitting(for: update) }

    /// The libretto another career last showed, read from that career's offline record.
    ///
    /// The token is bound to one matricola, so this is the only way to see a second
    /// career's plan without switching to it.
    ///
    /// - Parameters:
    ///   - account: The other career's matricola.
    ///   - store: Where to read from.
    /// - Returns: The teachings, or `nil` when that career has no record on this device.
    static func cachedLibretto(account: String, store: OfflineStore = .shared) -> [LibrettoExam]? {
        store.load(CareerSource.Payload.self, as: CareerSource.id, account: account)?
            .value.libretto
    }

    // MARK: - Loading

    /// Loads the record, then tells ``UpdateFeed`` what it found and writes the widgets'
    /// snapshot.
    ///
    /// The feed is pointed at the current account before the load rather than after, so
    /// signing out clears it whether or not anything is fetched. The feed is told what
    /// changed only after a load that got somewhere: what is held after a failure is the
    /// cached record, and re-recording it would have the feed reasoning about data it has
    /// already seen.
    ///
    /// - Parameter force: Bypasses the store's load window.
    func load(force: Bool = false) async {
        // Before the load, not after: signing out must clear the feed whether
        // or not anything is fetched.
        if account.isSample {
            // `deadlines:` is left at its empty default: the sample feed
            // carries exam updates only.
            feed.showSample(ExamUpdate.samples())
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

    /// Writes the narrow view of the career the widgets read, and asks the career widget
    /// to reload.
    ///
    /// Separate from the store's offline copy, so a widget does not decode a student's
    /// whole exam record to show one number.
    ///
    /// - Parameter account: The matricola the snapshot is keyed by.
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
    /// A write to the real system, so it happens only when the student presses save. The
    /// figure is held locally either way, and an undeliverable write is queued through
    /// ``PendingChanges``.
    ///
    /// - Parameter media: The target the student chose.
    /// - Returns: `true` when the write reached Servizi Online, `false` when it was
    ///   queued or there is no matricola.
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
/// ``CareerModel`` satisfies ``StudentRecord`` as it stands.
///
/// Declared here rather than beside the protocol: ``StudentRecord`` refines
/// `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive — a warning today and an error in a later language mode.
extension CareerModel: StudentRecord {}
