import Foundation
import Observation
import OSLog

/// Career statistics and exam sittings.
///
/// Two endpoints on two different hosts:
/// - `GET /rest/me/polimi/{matricola}` (app host) — mean, CFU, exam counts
/// - `GET /rest/v1/insegn` (exams host) — teachings, each with `appelliEsame`
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
        // should not delay the other.
        async let bookTask = loadGradeBook(matricola: matricola)
        async let sessionsTask = loadSessions()

        let (book, loadedSessions) = await (bookTask, sessionsTask)

        if let book { gradeBook = book }
        if let loadedSessions { sessions = loadedSessions }

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
                APIRequest(host: .app, path: "/rest/me/polimi/\(matricola)"),
                as: GradeBookDTO.self
            )
            return dto.toGradeBook()
        } catch {
            log.error("Gradebook failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadSessions() async -> [ExamSession]? {
        do {
            let response = try await session.api.send(
                APIRequest(
                    host: .exams,
                    path: "/rest/v1/insegn",
                    query: [.init(name: "lang", value: "IT")]
                ),
                as: TeachingsResponse.self
            )
            return response.INSEGN.flatMap { $0.toExamSessions() }
        } catch {
            log.error("Exam sessions failed: \(error.localizedDescription)")
            return nil
        }
    }
}
