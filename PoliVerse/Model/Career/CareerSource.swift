import Foundation
import OSLog

/// The ``Resource`` for the student's academic record: grade book, libretto, sittings,
/// plan header and the target average set on Servizi Online.
///
/// Six independent endpoints across three hosts, fetched concurrently because they
/// are one screen and one being slow should not delay the rest. Each may fail on its
/// own — a missing target average is the common case rather than an error — and the
/// fetch throws only when both load-bearing calls came back empty.
nonisolated struct CareerSource: Resource {
    /// Names the offline record and the log category.
    static let id = "career"
    /// Fifteen minutes: marks are published in batches rather than continuously.
    static let ttl: TimeInterval = 900
    /// Timed in the performance report as the career load.
    static let signpost: PerfSignpost.Name? = .careerLoad

    /// Diagnostic log for this type, under the `career` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "career")

    /// Everything one career load produces.
    ///
    /// Persisted between launches, libretto and sittings included: a student's exam
    /// record and their next exam should not disappear because they are on a train.
    struct Payload: Codable, Sendable, Equatable {
        /// The aggregate figures, with the exam counts filled in from the counters call.
        var gradeBook = GradeBook.empty
        /// Every exam sitting known.
        var sessions: [ExamSession] = []
        /// The study plan with its results.
        var libretto: [LibrettoExam] = []
        /// The plan's header, where the endpoint answered.
        var planHeader: StudyPlanHeader?
        /// The target average the student set on Servizi Online, or `nil` when they set none.
        var officialTarget: Double?
        /// Whether the Politecnico accepted the sign-in but refuses this account's profile
        /// for the exam services.
        ///
        /// Permanent for this account, so it is not shown as a retryable error. Not
        /// persisted: it describes the token rather than the student's record.
        var servicesRefused = false

        /// Every stored property except ``Payload/servicesRefused``, which describes the
        /// token rather than the record.
        private enum CodingKeys: String, CodingKey {
            case gradeBook, sessions, libretto, planHeader, officialTarget
        }
    }

    /// Both load-bearing calls came back empty, so there is nothing to show that was not
    /// already on screen. ``Query`` keeps the previous value on this error.
    struct NothingLoaded: Error {}

    /// Fetches the whole record.
    ///
    /// The six calls run concurrently and each returns `nil` on failure. With a
    /// record already held (`previous`), each answer is shown over it as it lands,
    /// through ``Partial``. The exam counts
    /// come from the counters call, and the planned count is derived from the distinct
    /// teachings in the sittings when the counters call fails.
    ///
    /// - Parameter env: The transport and the matricola.
    /// - Returns: The record, with a `nil` piece left at its default.
    /// - Throws: ``AuthError/notAuthenticated`` without a matricola, or ``NothingLoaded``
    ///   when neither the grade book nor the sittings loaded.
    @concurrent
    func fetch(_ key: Whole, env: Env, previous: Payload?) async throws -> Payload {
        guard let matricola = env.matricola else { throw AuthError.notAuthenticated }
        let refused = RefusalFlag()

        // Independent endpoints, so run them together, and take each as it
        // lands: with a career already on screen, every part that arrives is
        // shown over it at once, rather than all six waiting for the slowest.
        var parts = Parts()
        await withTaskGroup(of: Part.self) { group in
            group.addTask(name: "career gradebook") { .book(await Self.gradeBook(matricola: matricola, env, refused)) }
            group.addTask(name: "career counters") { .counters(await Self.counters(env, refused)) }
            group.addTask(name: "career sittings") { .sessions(await Self.sessions(env, refused)) }
            group.addTask(name: "career libretto") { .libretto(await Self.libretto(matricola: matricola, env, refused)) }
            group.addTask(name: "career target") { .target(await Self.target(matricola: matricola, env)) }
            group.addTask(name: "career plan header") { .header(await Self.planHeader(matricola: matricola, env)) }
            for await part in group {
                parts.add(part)
                if let previous, !parts.isComplete {
                    await Partial.report(parts.payload(over: previous))
                }
            }
        }

        guard parts.book != nil || parts.sessions != nil else { throw NothingLoaded() }
        var payload = parts.payload(over: Payload())
        payload.servicesRefused = await refused.value
        return payload
    }

    /// One endpoint's answer, `nil` when it failed.
    private enum Part: Sendable {
        case book(GradeBook?)
        case counters(ExamCountersDTO?)
        case sessions([ExamSession]?)
        case libretto([LibrettoExam]?)
        case target(Double?)
        case header(StudyPlanHeader?)
    }

    /// The answers so far, and how they make a career.
    private struct Parts {
        var book: GradeBook?
        var counters: ExamCountersDTO?
        var sessions: [ExamSession]?
        var libretto: [LibrettoExam]?
        var target: Double?
        var header: StudyPlanHeader?
        /// How many of the six have answered, failed ones included.
        private var answered = 0

        var isComplete: Bool { answered == 6 }

        mutating func add(_ part: Part) {
            answered += 1
            switch part {
            case .book(let value): book = value
            case .counters(let value): counters = value
            case .sessions(let value): sessions = value
            case .libretto(let value): libretto = value
            case .target(let value): target = value
            case .header(let value): header = value
            }
        }

        /// The career from what has answered, laid over `base`: a part not
        /// back yet, or failed, keeps what `base` had.
        ///
        /// Over an empty base this is exactly the career the six calls make
        /// together; over the career shown before, a partial update of it.
        func payload(over base: Payload) -> Payload {
            var payload = base
            if let libretto { payload.libretto = libretto }
            if let target { payload.officialTarget = target }
            if let header { payload.planHeader = header }
            if var book {
                // The gradebook endpoint no longer carries exam counts; they come
                // from the IAE counters call instead.
                if let counters {
                    book.examsSubscribed = counters.num_iscriz ?? 0
                    book.examsGiven = counters.num_esiti ?? 0
                } else if base.gradeBook.examsGiven > 0 || base.gradeBook.examsSubscribed > 0 {
                    // Counters not back yet: the counts shown before stand.
                    book.examsSubscribed = base.gradeBook.examsSubscribed
                    book.examsGiven = base.gradeBook.examsGiven
                }
                if book.examsPlanned == 0 { book.examsPlanned = base.gradeBook.examsPlanned }
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
    }

    /// The sample record: grade book, sittings and libretto.
    func sample(_ key: Whole) -> Payload? {
        Payload(gradeBook: .sample, sessions: ExamSession.samples(),
                libretto: LibrettoExam.samples())
    }

    /// Collects “this account is not entitled” across the six concurrent calls.
    private actor RefusalFlag {
        /// Whether any call was refused for this account's profile.
        private(set) var value = false
        /// Records a refusal.
        func raise() { value = true }
    }

    // MARK: - The six calls
    //
    // Each returns nil rather than throwing: one service being down is not the
    // career being unavailable, and the caller decides what a missing piece
    // means.

    /// Fetches the aggregate figures.
    ///
    /// - Parameters:
    ///   - matricola: Whose figures to fetch.
    ///   - env: The transport.
    ///   - refused: Raised when the account is not entitled.
    /// - Returns: The grade book, or `nil` on any failure.
    private static func gradeBook(matricola: String, _ env: Env,
                                  _ refused: RefusalFlag) async -> GradeBook? {
        await attempt("Gradebook", refused) {
            let data = try await env.http.data(
                for: APIRequest(host: .app, path: "/v1/io-e-polimi/\(matricola)"))
            return try await BackgroundJSON.decode(GradeBookDTO.self, from: data,
                                                   iso8601Dates: true).toGradeBook()
        }
    }

    /// Fetches the exam counters.
    ///
    /// - Parameters:
    ///   - env: The transport.
    ///   - refused: Raised when the account is not entitled.
    /// - Returns: The counters, or `nil` on any failure.
    private static func counters(_ env: Env, _ refused: RefusalFlag) async -> ExamCountersDTO? {
        await attempt("Exam counters", refused) {
            let data = try await env.http.data(
                for: APIRequest(host: .iae, path: "/v1/base/counters"))
            return try await BackgroundJSON.decode(ExamCountersDTO.self, from: data,
                                                   iso8601Dates: true)
        }
    }

    /// Fetches every exam sitting, from the same `/v1/insegn` response the course list
    /// uses.
    ///
    /// - Parameters:
    ///   - env: The transport.
    ///   - refused: Raised when the account is not entitled.
    /// - Returns: The sittings, or `nil` on any failure.
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

    /// Fetches the study plan with its results.
    ///
    /// - Parameters:
    ///   - matricola: Whose libretto to fetch.
    ///   - env: The transport.
    ///   - refused: Raised when the account is not entitled.
    /// - Returns: The teachings, or `nil` on any failure.
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

    /// Fetches the target average the student set on Servizi Online.
    ///
    /// Read leniently through ``JSONValue`` across several candidate field names, since
    /// the payload's shape is not pinned down. A missing target is the common case rather
    /// than a failure, so no refusal is recorded for it.
    ///
    /// - Parameters:
    ///   - matricola: Whose target to fetch.
    ///   - env: The transport.
    /// - Returns: The target, or `nil` when none is set or the call failed.
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

    /// Fetches the study plan's header, read leniently through ``JSONValue``.
    ///
    /// - Parameters:
    ///   - matricola: Whose plan header to fetch.
    ///   - env: The transport.
    /// - Returns: The header, or `nil` on any failure.
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

    /// Runs one call, turning any failure into `nil` and recording a refusal.
    ///
    /// A cancellation is swallowed without a log line: it means the view that asked went
    /// away, which is not a failure.
    ///
    /// - Parameters:
    ///   - name: The call's name, for the log.
    ///   - refused: Raised on ``APIError/notEntitled(_:body:)``, or `nil` for a call whose
    ///     absence is normal.
    ///   - body: The call to run.
    /// - Returns: The call's result, or `nil` when it failed.
    private static func attempt<T>(
        _ name: String, _ refused: RefusalFlag?, _ body: () async throws -> T?
    ) async -> T? {
        // Each endpoint timed on its own: `career.load` is the slowest of six,
        // and which one is slow decides what is worth showing first.
        let started = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - started
            log.notice("\(name, privacy: .public) took \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000, privacy: .public) ms")
        }
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
