import Foundation
import OSLog

/// The student's academic record: gradebook, libretto, sittings, and the
/// target average they set on Servizi Online.
///
/// Six independent endpoints across three hosts, fetched together because they
/// are one screen and one of them being slow or down should not delay the rest.
/// Each is allowed to fail on its own — a missing target average is the common
/// case, not an error — and the fetch only throws when *both* load-bearing
/// calls came back empty.
nonisolated struct CareerSource: Source {
    static let id = "career"
    /// Fifteen minutes: marks are published in batches, not continuously.
    static let ttl: TimeInterval = 900
    static let signpost: PerfSignpost.Name? = .careerLoad

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "career")

    /// What is kept between launches.
    ///
    /// The libretto in particular is a student's exam record and there is no
    /// reason they should lose sight of it because they are on a train. The
    /// sittings are kept for the same reason — they were not, before, so the
    /// "next exam" figure vanished offline.
    struct Payload: Codable, Sendable, Equatable {
        var gradeBook = GradeBook.empty
        var sessions: [ExamSession] = []
        var libretto: [LibrettoExam] = []
        var planHeader: StudyPlanHeader?
        var officialTarget: Double?
        /// The Politecnico accepted the login but refuses this account's
        /// profile for the exam services. Not an error to show as one — it is
        /// permanent for this user, so retrying is pointless.
        ///
        /// Not persisted: it describes this token, not this student's record.
        var servicesRefused = false

        private enum CodingKeys: String, CodingKey {
            case gradeBook, sessions, libretto, planHeader, officialTarget
        }
    }

    /// Both load-bearing calls came back empty, so there is nothing to show
    /// that was not already on screen.
    struct NothingLoaded: Error {}

    func fetch(_ env: Env) async throws -> Payload {
        guard let matricola = env.matricola else { throw AuthError.notAuthenticated }
        let refused = RefusalFlag()

        // Independent endpoints, so run them together.
        async let bookTask = Self.gradeBook(matricola: matricola, env, refused)
        async let countersTask = Self.counters(env, refused)
        async let sessionsTask = Self.sessions(env, refused)
        async let librettoTask = Self.libretto(matricola: matricola, env, refused)
        async let targetTask = Self.target(matricola: matricola, env)
        async let headerTask = Self.planHeader(matricola: matricola, env)

        let (book, counters, sessions, libretto) =
            await (bookTask, countersTask, sessionsTask, librettoTask)

        guard book != nil || sessions != nil else { throw NothingLoaded() }

        var payload = Payload()
        payload.libretto = libretto ?? []
        payload.officialTarget = await targetTask
        payload.planHeader = await headerTask
        payload.servicesRefused = await refused.value

        if var book {
            // The gradebook endpoint no longer carries exam counts; they come
            // from the IAE counters call instead.
            if let counters {
                book.examsSubscribed = counters.num_iscriz ?? 0
                book.examsGiven = counters.num_esiti ?? 0
            }
            payload.gradeBook = book
        }
        if let sessions {
            payload.sessions = sessions
            // `/v1/insegn` knows the whole plan, so the planned count is
            // derivable even when the counters call fails.
            if payload.gradeBook.examsPlanned == 0 {
                payload.gradeBook.examsPlanned = Set(sessions.map(\.courseCode)).count
            }
        }
        return payload
    }

    func sample() -> Payload {
        Payload(gradeBook: .sample, sessions: ExamSession.samples(),
                libretto: LibrettoExam.samples())
    }

    /// Collects "this account is not entitled" across the six concurrent calls.
    private actor RefusalFlag {
        private(set) var value = false
        func raise() { value = true }
    }

    // MARK: - The six calls
    //
    // Each returns nil rather than throwing: one service being down is not the
    // career being unavailable, and the caller decides what a missing piece
    // means.

    private static func gradeBook(matricola: String, _ env: Env,
                                  _ refused: RefusalFlag) async -> GradeBook? {
        await attempt("Gradebook", refused) {
            let data = try await env.http.data(
                for: APIRequest(host: .app, path: "/v1/io-e-polimi/\(matricola)"))
            return try await BackgroundJSON.decode(GradeBookDTO.self, from: data,
                                                   iso8601Dates: true).toGradeBook()
        }
    }

    private static func counters(_ env: Env, _ refused: RefusalFlag) async -> ExamCountersDTO? {
        await attempt("Exam counters", refused) {
            let data = try await env.http.data(
                for: APIRequest(host: .iae, path: "/v1/base/counters"))
            return try await BackgroundJSON.decode(ExamCountersDTO.self, from: data,
                                                   iso8601Dates: true)
        }
    }

    private static func sessions(_ env: Env, _ refused: RefusalFlag) async -> [ExamSession]? {
        await attempt("Exam sessions", refused) {
            let data = try await env.http.data(for: APIRequest(
                host: .iae,
                path: "/v1/insegn",
                query: [.init(name: "lang", value: PoliMiLanguage.current.rawValue)]
            ))
            let response = try await BackgroundJSON.decode(TeachingsResponse.self, from: data,
                                                           iso8601Dates: true)
            let sittings = response.teachings.flatMap { $0.toExamSessions() }
            log.notice("insegn yielded \(sittings.count, privacy: .public) exam sittings")
            return sittings
        }
    }

    /// `GET {libretto}/elencoinsegnamenti/{matricola}` — the study plan with
    /// results.
    private static func libretto(matricola: String, _ env: Env,
                                 _ refused: RefusalFlag) async -> [LibrettoExam]? {
        await attempt("Libretto", refused) {
            let data = try await env.http.data(
                for: APIRequest(host: .libretto, path: "/elencoinsegnamenti/\(matricola)"))
            let response = try await BackgroundJSON.decode(LibrettoResponse.self, from: data,
                                                           iso8601Dates: true)
            let exams = response.allExams
            log.notice("libretto: \(response.sostenuti?.count ?? 0, privacy: .public) passed, \(response.daSostenere?.count ?? 0, privacy: .public) pending, \(exams.count, privacy: .public) usable")
            return exams
        }
    }

    /// `GET {libretto}/mediaobiettivo/{matricola}` — the target the student set
    /// on Servizi Online. Shape unconfirmed, so it is read leniently; a missing
    /// target is the common case and not a failure.
    private static func target(matricola: String, _ env: Env) async -> Double? {
        await attempt("Target average", nil) {
            let data = try await env.http.data(
                for: APIRequest(host: .libretto, path: "/mediaobiettivo/\(matricola)"))
            #if DEBUG
            log.notice("mediaobiettivo shape: \(JSONShape.describe(data), privacy: .public)")
            #endif
            let value = try await BackgroundJSON.decode(JSONValue.self, from: data)
            let fields = value.objectValue ?? value.arrayValue?.first?.objectValue
            return fields?.firstValue([
                "media", "media_obiettivo", "mediaObiettivo", "valore", "target",
            ])?.doubleValue
        } ?? nil
    }

    /// `GET {libretto}/testatapiano/{matricola}` — the plan's header.
    private static func planHeader(matricola: String, _ env: Env) async -> StudyPlanHeader? {
        await attempt("Study plan header", nil) {
            let data = try await env.http.data(
                for: APIRequest(host: .libretto, path: "/testatapiano/\(matricola)"))
            #if DEBUG
            log.notice("testatapiano shape: \(JSONShape.describe(data), privacy: .public)")
            #endif
            return StudyPlanHeader(value: try await BackgroundJSON.decode(JSONValue.self, from: data))
        } ?? nil
    }

    /// Runs one call, turning any failure into nil and noting a refusal.
    ///
    /// Cancellation is swallowed without a log line: it means the view that
    /// asked went away, which is not a failure and was the largest source of
    /// noise in this file's logs.
    private static func attempt<T>(
        _ name: String, _ refused: RefusalFlag?, _ body: () async throws -> T?
    ) async -> T? {
        do {
            return try await body()
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            if case APIError.notEntitled = error { await refused?.raise() }
            log.error("\(name, privacy: .public) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
