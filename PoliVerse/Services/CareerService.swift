import Foundation
import Observation
import OSLog
import WidgetKit

/// Career statistics and exam sittings.
///
/// Three endpoints, all taken from the official web app's own bundle:
///
/// | Call | Gives |
/// | --- | --- |
/// | `GET {app}/v1/io-e-polimi/{matricola}` | `mean`, `given_cfu`, `planned_cfu` |
/// | `GET {iae}/v1/base/counters` | `num_iscriz`, `num_esiti` |
/// | `GET {iae}/v1/insegn?lang=IT` | teachings, each with `appelliEsame` |
///
/// PoliFemo's `/rest/me/polimi/{matricola}` 404s; `/v1/io-e-polimi/…` is what
/// replaced it, with the field names intact.
@Observable
final class CareerService {
    private(set) var gradeBook: GradeBook = .empty
    private(set) var sessions: [ExamSession] = []
    /// The libretto: every teaching in the plan, with its result.
    private(set) var libretto: [LibrettoExam] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// How old the data on screen is, so the UI can say so rather than
    /// present a cached libretto as current.
    private(set) var age: TimeInterval?
    /// Set when the Politecnico refuses this account the exam services
    /// outright — "Utente non abilitato Code: 6" from `iae`.
    ///
    /// Kept apart from ``errorMessage`` because it is not a fault and a fresh
    /// login does not clear it: the account is genuinely not enabled for exam
    /// registration at the moment, which is a thing to explain rather than a
    /// thing to retry.
    private(set) var examServicesRefused = false
    /// The target average the student set on Servizi Online, where they have
    /// one. Read rather than invented: the app's own slider is a what-if, and
    /// this is the figure the Politecnico is holding.
    private(set) var officialTarget: Double?
    /// Header of the study plan — course name, year, track.
    private(set) var planHeader: StudyPlanHeader?

    /// Everything needed for the plan and the simulator.
    var studyPlan: StudyPlan { StudyPlan(exams: libretto) }

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "career")
    private var window = LoadWindow()

    /// Identifies the data currently held, so a change of account — or of the
    /// sample-data toggle — always reloads instead of waiting out the window.
    private var source: String {
        session.useMockData ? "mock" : (session.student?.matricola ?? "anonymous")
    }


    private var slot: CachedSlot<Cached>
    var pending: PendingChanges?

    /// What is kept between launches. The libretto in particular is a
    /// student's exam record and there is no reason they should lose sight of
    /// it because they are on a train.
    private nonisolated struct Cached: Codable, Sendable {
        var gradeBook: GradeBook
        var libretto: [LibrettoExam]
        var planHeader: StudyPlanHeader?
        var officialTarget: Double?
    }

    init(session: Session, offline: OfflineStore = .shared) {
        self.session = session
        self.slot = CachedSlot(name: "career", store: offline)
    }

    /// Shows the last known figures before any request.
    ///
    /// Called from `load()`, not from `init()`: services are built inside the
    /// App's initialiser, and the matricola is not known until
    /// `Session.restore()` has run, which is later. Restoring at construction
    /// asked for account nil and silently restored nothing.
    private func restoreCache() {
        guard let cached = slot.restore(for: session.student?.matricola) else { return }
        gradeBook = cached.gradeBook
        libretto = cached.libretto
        planHeader = cached.planHeader
        officialTarget = cached.officialTarget
        age = slot.age
    }

    /// Passed exams, most recent first.
    ///
    /// Sourced from the libretto rather than from exam sittings: sittings
    /// disappear from `/v1/insegn` once there is nothing left to register for,
    /// so a student who has passed everything would see an empty list.
    var passedExams: [LibrettoExam] {
        libretto
            .filter(\.isPassed)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Teachings in the plan with no result yet.
    var pendingExams: [LibrettoExam] {
        libretto.filter { !$0.isPassed }.sorted { $0.name < $1.name }
    }

    /// Average of the numeric marks actually recorded, weighted by CFU where
    /// known. Shown only as a cross-check against the official mean.
    var weightedMean: Double? {
        let graded = libretto.compactMap { exam -> (Int, Int)? in
            guard let grade = exam.grade, grade > 0 else { return nil }
            return (grade, exam.cfu ?? 0)
        }
        guard !graded.isEmpty else { return nil }
        let totalCFU = graded.reduce(0) { $0 + $1.1 }
        guard totalCFU > 0 else {
            return Double(graded.reduce(0) { $0 + $1.0 }) / Double(graded.count)
        }
        return graded.reduce(0.0) { $0 + Double($1.0 * $1.1) } / Double(totalCFU)
    }

    /// Sittings still ahead, soonest first.
    var upcoming: [ExamSession] {
        sessions
            .filter { $0.grade == nil && ($0.date ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Sittings the student is signed up for.
    var enrolled: [ExamSession] {
        upcoming.filter { $0.status == .enrolled }
    }

    /// - Parameter force: set by pull-to-refresh. Without it, a load that ran
    ///   recently is skipped — see ``LoadWindow``.
    func load(force: Bool = false) async {
        guard !isLoading, window.shouldLoad(force: force, source: source) else { return }
        isLoading = true
        errorMessage = nil
        examServicesRefused = false
        defer { isLoading = false }

        restoreCache()

        if session.useMockData {
            gradeBook = MockData.gradeBook
            sessions = MockData.examSessions()
            libretto = MockData.libretto()
            window.markLoaded(source: source)
            return
        }

        guard let matricola = session.student?.matricola else {
            errorMessage = AuthError.notAuthenticated.localizedDescription
            return
        }

        // Independent endpoints, so run them together — one being slow or down
        // should not delay the others.
        async let bookTask = loadGradeBook(matricola: matricola)
        async let countersTask = loadCounters()
        async let sessionsTask = loadSessions()
        async let librettoTask = loadLibretto(matricola: matricola)
        async let targetTask = loadTarget(matricola: matricola)
        async let headerTask = loadPlanHeader(matricola: matricola)

        let (book, counters, loadedSessions, loadedLibretto) =
            await (bookTask, countersTask, sessionsTask, librettoTask)
        officialTarget = await targetTask
        planHeader = await headerTask

        if let loadedLibretto { libretto = loadedLibretto }

        if var book {
            // The gradebook endpoint no longer carries exam counts; they come
            // from the IAE counters call instead.
            if let counters {
                book.examsSubscribed = counters.num_iscriz ?? 0
                book.examsGiven = counters.num_esiti ?? 0
            }
            gradeBook = book
        }
        if let loadedSessions {
            sessions = loadedSessions
            // `/v1/insegn` knows the whole plan, so the planned count is
            // derivable even when the counters call fails.
            if gradeBook.examsPlanned == 0 {
                gradeBook.examsPlanned = Set(loadedSessions.map(\.courseCode)).count
            }
        }

        if book == nil && loadedSessions == nil {
            errorMessage = examServicesRefused
                ? nil
                : String(localized: "Impossibile caricare i dati di carriera.")
            // Deliberately **not** cleared any more.
            //
            // This used to set the gradebook, the sittings and the libretto
            // to empty, which meant losing signal replaced a student's exam
            // record with a blank screen. What is held is real data that was
            // theirs; it is kept, and its age is shown instead.
            //
            // Still no mock fallback: an invented weighted average is the last
            // thing anyone should see presented as their own.
            // Left unmarked on purpose: the next visit retries rather than
            // sitting on an error for the whole window.
            return
        }
        window.markLoaded(source: source)
        slot.save(
            Cached(gradeBook: gradeBook, libretto: libretto,
                   planHeader: planHeader, officialTarget: officialTarget),
            for: session.useMockData ? nil : matricola)
        age = slot.age
        saveWidgetSnapshot(for: session.useMockData ? nil : matricola)
    }

    /// Writes the narrow view of the career that the widgets read.
    ///
    /// Separate from `slot`, and deliberately so — see ``CareerSnapshot``.
    private func saveWidgetSnapshot(for account: String?) {
        guard let account else { return }
        let next = sessions
            .compactMap { session -> (String, Date)? in
                guard let date = session.date, date > .now,
                      session.grade == nil else { return nil }
                return (session.courseName, date)
            }
            .min { $0.1 < $1.1 }

        let snapshot = CareerSnapshot(
            mean: gradeBook.mean,
            earnedCFU: gradeBook.earnedCFU,
            plannedCFU: gradeBook.plannedCFU,
            examsGiven: gradeBook.examsGiven,
            examsPlanned: gradeBook.examsPlanned,
            nextExamName: next?.0,
            nextExamDate: next?.1)
        OfflineStore.shared.save(snapshot, as: CareerSnapshot.cacheName, account: account)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `GET {libretto}/mediaobiettivo/{matricola}` — the target the student
    /// set on Servizi Online. Shape unconfirmed, so it is read leniently and
    /// logged; a missing target is the common case and not a failure.
    private func loadTarget(matricola: String) async -> Double? {
        do {
            let data = try await session.api.send(
                APIRequest(host: .libretto, path: "/mediaobiettivo/\(matricola)"))
            log.notice("mediaobiettivo shape: \(JSONShape.describe(data), privacy: .public)")
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            let fields = value.objectValue ?? value.arrayValue?.first?.objectValue
            return fields?.firstValue([
                "media", "media_obiettivo", "mediaObiettivo", "valore", "target",
            ])?.doubleValue
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            log.error("Target average failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// `GET {libretto}/testatapiano/{matricola}` — the plan's header.
    private func loadPlanHeader(matricola: String) async -> StudyPlanHeader? {
        do {
            let data = try await session.api.send(
                APIRequest(host: .libretto, path: "/testatapiano/\(matricola)"))
            log.notice("testatapiano shape: \(JSONShape.describe(data), privacy: .public)")
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            return StudyPlanHeader(value: value)
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            log.error("Study plan header failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves a target average back to Servizi Online.
    ///
    /// `PUT /mediaobiettivo/insertmediaobiettivo` with `{matricola, media}`,
    /// exactly as the official app sends it. A write to the real system, so it
    /// happens only when the user presses save — never from the slider.
    func saveTarget(_ media: Double) async -> Bool {
        guard let matricola = session.student?.matricola else { return false }
        let body = try? JSONSerialization.data(
            withJSONObject: ["matricola": matricola, "media": media])
        do {
            _ = try await session.api.send(APIRequest(
                host: .libretto,
                path: "/mediaobiettivo/insertmediaobiettivo",
                method: "PUT",
                body: body))
            officialTarget = media
            log.notice("Saved target average \(media, privacy: .public)")
            return true
        } catch {
            log.error("Could not save the target: \(error.localizedDescription)")
            // Kept locally and queued: the figure the student chose is theirs,
            // and losing it because a tunnel arrived first would be rude.
            officialTarget = media
            pending?.record(.targetAverage(media))
            return false
        }
    }

    private func loadGradeBook(matricola: String) async -> GradeBook? {
        do {
            let dto = try await session.api.send(
                APIRequest(host: .app, path: "/v1/io-e-polimi/\(matricola)"),
                as: GradeBookDTO.self
            )
            return dto.toGradeBook()
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            if case APIError.notEntitled = error { examServicesRefused = true }
            log.error("Gradebook failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// `GET {libretto}/elencoinsegnamenti/{matricola}` — the study plan with
    /// results.
    private func loadLibretto(matricola: String) async -> [LibrettoExam]? {
        do {
            let response = try await session.api.send(
                APIRequest(host: .libretto, path: "/elencoinsegnamenti/\(matricola)"),
                as: LibrettoResponse.self
            )
            let exams = response.allExams
            log.notice("libretto: \(response.sostenuti?.count ?? 0, privacy: .public) passed, \(response.daSostenere?.count ?? 0, privacy: .public) pending, \(exams.count, privacy: .public) usable")
            return exams
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            if case APIError.notEntitled = error { examServicesRefused = true }
            log.error("Libretto failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadCounters() async -> ExamCountersDTO? {
        do {
            return try await session.api.send(
                APIRequest(host: .iae, path: "/v1/base/counters"),
                as: ExamCountersDTO.self
            )
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            if case APIError.notEntitled = error { examServicesRefused = true }
            log.error("Exam counters failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadSessions() async -> [ExamSession]? {
        do {
            let response = try await session.api.send(
                APIRequest(
                    host: .iae,
                    path: "/v1/insegn",
                    query: [.init(name: "lang", value: PoliMiLanguage.current.rawValue)]
                ),
                as: TeachingsResponse.self
            )
            let sittings = response.teachings.flatMap { $0.toExamSessions() }
            log.notice("insegn yielded \(sittings.count, privacy: .public) exam sittings")
            return sittings
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            if case APIError.notEntitled = error { examServicesRefused = true }
            log.error("Exam sessions failed: \(error.localizedDescription)")
            return nil
        }
    }
}
