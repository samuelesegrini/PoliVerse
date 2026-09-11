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
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "career")

    init(session: Session) {
        self.session = session
    }

    /// Sittings with a published mark, most recent first.
    var results: [ExamSession] {
        sessions
            .filter { $0.grade != nil }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
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

        let (book, counters, loadedSessions) = await (bookTask, countersTask, sessionsTask)

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
