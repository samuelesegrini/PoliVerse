import Foundation
import Observation
import OSLog

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

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "career")

    init(session: Session) {
        self.session = session
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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if session.useMockData {
            gradeBook = MockData.gradeBook
            sessions = MockData.examSessions()
            libretto = MockData.libretto()
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

        let (book, counters, loadedSessions, loadedLibretto) =
            await (bookTask, countersTask, sessionsTask, librettoTask)

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
            errorMessage = "Impossibile caricare i dati di carriera."
            // No mock fallback — an invented weighted average is the last thing
            // a student should see presented as their own.
            gradeBook = .empty
            sessions = []
            libretto = []
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
                    query: [.init(name: "lang", value: "IT")]
                ),
                as: TeachingsResponse.self
            )
            let sittings = response.teachings.flatMap { $0.toExamSessions() }
            log.notice("insegn yielded \(sittings.count, privacy: .public) exam sittings")
            return sittings
        } catch {
            log.error("Exam sessions failed: \(error.localizedDescription)")
            return nil
        }
    }
}
