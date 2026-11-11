import Foundation
import OSLog

/// The ``Resource`` for the student's academic record: grade book, libretto, sittings,
/// plan header and the target average set on Servizi Online.
///
/// Six independent endpoints across three hosts, fetched concurrently because they
/// are one screen and one being slow should not delay the rest. Each is a ``Part``:
/// it may fail on its own, is shown and stored as soon as it answers, and is asked
/// again only when it is old. The fetch throws only when both load-bearing calls
/// came back empty.
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

    /// The requests a career is made of. Each fills its own section of the screen,
    /// is kept with its own age, and is asked again on its own.
    enum Part: String, Hashable, Sendable, CaseIterable {
        /// The aggregate figures: average, credits.
        case book
        /// How many exams were sat and registered for.
        case counters
        /// The exam sittings.
        case sittings
        /// The study plan with its results.
        case libretto
        /// The target average set on Servizi Online.
        case target
        /// The plan's header: the degree course and the year.
        case header
    }

    /// The header and the target change a few times a year; the rest as marks are
    /// published.
    static func maxAge(of part: Part) -> TimeInterval {
        switch part {
        case .target, .header: 86_400
        case .book, .counters, .sittings, .libretto: ttl
        }
    }

    /// What of a sitting is worth pointing out when it changes. The count of
    /// students enrolled moves all day and the student's own enrolment is their
    /// doing, so neither is here.
    private struct SittingFacts: Identifiable, Equatable {
        let id: Int
        let date: Date?
        let room: String?
        /// The enrolment window has opened. Still `true` once the student has
        /// enrolled, the window has shut or a mark is out, so none of those is
        /// a change by itself.
        let hasOpened: Bool
        let grade: String?
        let refusable: Bool
        let hasCorrections: Bool

        init(_ sitting: ExamSession) {
            id = sitting.id
            date = sitting.date
            room = sitting.room?.trimmingCharacters(in: .whitespaces)
            hasOpened = sitting.status != .notYetOpen
            grade = sitting.grade?.display
            refusable = sitting.grade?.refusable ?? false
            hasCorrections = sitting.hasCorrections
        }
    }

    /// What of a libretto row is worth pointing out when it changes: its result.
    private struct ResultFacts: Identifiable, Equatable {
        let id: String
        let isPassed: Bool
        let grade: Int?
        let hasLode: Bool

        init(_ exam: LibrettoExam) {
            id = exam.id
            isPassed = exam.isPassed
            grade = exam.grade
            hasLode = exam.hasLode
        }
    }

    /// The sittings and the libretto have items with stable ids; the figures do not.
    func changes(in part: Part, from old: Payload, to new: Payload) -> ChangeSet {
        switch part {
        case .sittings:
            ChangeDetector.changes(from: old.sessions.map(SittingFacts.init), to: new.sessions.map(SittingFacts.init))
        case .libretto:
            ChangeDetector.changes(from: old.libretto.map(ResultFacts.init), to: new.libretto.map(ResultFacts.init))
        case .book, .counters, .target, .header:
            ChangeSet()
        }
    }

    /// Fetches the whole record in one go, for a caller outside the loader.
    ///
    /// - Parameter env: The transport and the matricola.
    /// - Returns: The record, laid over `previous`.
    /// - Throws: As ``fetch(_:env:parts:over:progress:)``.
    @concurrent
    func fetch(_ key: Whole, env: Env, previous: Payload?) async throws -> Payload {
        try await fetch(key, env: env, parts: Set(Part.allCases), over: previous, progress: LoadProgress()).value
    }

    /// Fetches some parts of the record.
    ///
    /// The calls run concurrently and each may fail on its own. After every answer
    /// the record so far, laid over the one held, is reported with the parts in it,
    /// so a section is shown as soon as its own request is back. The exam counts
    /// come from the counters call, and the planned count is derived from the
    /// distinct teachings in the sittings when the counters call fails.
    ///
    /// - Parameters:
    ///   - env: The transport and the matricola.
    ///   - wanted: The parts to ask for.
    ///   - held: The record held, which a part not asked for, or failed, keeps.
    ///   - progress: Where the record is reported as it fills.
    /// - Returns: The record, with the parts that answered and those that failed.
    /// - Throws: ``AuthError/notAuthenticated`` without a matricola, or ``NothingLoaded``
    ///   when neither the grade book nor the sittings loaded of those asked, or
    ///   nothing at all did.
    @concurrent
    func fetch(_ key: Whole, env: Env, parts wanted: Set<Part>, over held: Payload?,
               progress: LoadProgress<CareerSource>) async throws -> LoadProgress<CareerSource>.Snapshot {
        guard let matricola = env.matricola else { throw AuthError.notAuthenticated }
        let refused = RefusalFlag()
        let base = held ?? Payload()

        // Independent endpoints, so run them together, and take each as it lands
        // rather than all waiting for the slowest.
        var parts = Parts()
        var arrived: Set<Part> = []
        var failed: Set<Part> = []
        await withTaskGroup(of: (Part, Answer, Bool).self) { group in
            for part in wanted {
                switch part {
                case .book:
                    group.addTask(name: "career gradebook") {
                        let value = await Self.gradeBook(matricola: matricola, env, refused)
                        return (Part.book, Answer.book(value), value != nil)
                    }
                case .counters:
                    group.addTask(name: "career counters") {
                        let value = await Self.counters(env, refused)
                        return (Part.counters, Answer.counters(value), value != nil)
                    }
                case .sittings:
                    group.addTask(name: "career sittings") {
                        let value = await Self.sessions(env, refused)
                        return (Part.sittings, Answer.sessions(value), value != nil)
                    }
                case .libretto:
                    group.addTask(name: "career libretto") {
                        let value = await Self.libretto(matricola: matricola, env, refused)
                        return (Part.libretto, Answer.libretto(value), value != nil)
                    }
                case .target:
                    group.addTask(name: "career target") {
                        let answer = await Self.target(matricola: matricola, env)
                        return (Part.target, Answer.target(answer?.value), answer != nil)
                    }
                case .header:
                    group.addTask(name: "career plan header") {
                        let value = await Self.planHeader(matricola: matricola, env)
                        return (Part.header, Answer.header(value), value != nil)
                    }
                }
            }
            for await (part, answer, answered) in group {
                parts.add(answer)
                if answered { arrived.insert(part) } else { failed.insert(part) }
                // Answered, and no target is set: the one shown before is gone.
                if part == .target, answered, case .target(.none) = answer { parts.clearsTarget = true }
                if !arrived.isEmpty, arrived.count + failed.count < wanted.count {
                    progress.report(parts.payload(over: base), arrived: arrived, failed: failed)
                }
            }
        }
        // A view going away is not six failures.
        try Task.checkCancellation()

        let bearing = wanted.intersection([.book, .sittings])
        guard bearing.isEmpty ? !arrived.isEmpty : !bearing.isDisjoint(with: arrived) else { throw NothingLoaded() }
        var payload = parts.payload(over: base)
        if !wanted.isDisjoint(with: [.book, .counters, .sittings, .libretto]) {
            payload.servicesRefused = await refused.value
        }
        return .init(value: payload, arrived: arrived, failed: failed)
    }

    /// One endpoint's answer, `nil` when it failed. Internal for the tests.
    enum Answer: Sendable {
        case book(GradeBook?)
        case counters(ExamCountersDTO?)
        case sessions([ExamSession]?)
        case libretto([LibrettoExam]?)
        case target(Double?)
        case header(StudyPlanHeader?)
    }

    /// The answers so far, and how they make a career. Internal for the tests.
    struct Parts {
        var book: GradeBook?
        var counters: ExamCountersDTO?
        var sessions: [ExamSession]?
        var libretto: [LibrettoExam]?
        var target: Double?
        var header: StudyPlanHeader?
        /// The target call answered that no target is set.
        var clearsTarget = false
        /// How many of the six have answered, failed ones included.
        private var answered = 0

        var isComplete: Bool { answered == 6 }

        mutating func add(_ part: Answer) {
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
            if let target { payload.officialTarget = target } else if clearsTarget { payload.officialTarget = nil }
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
            } else if let counters {
                // The counters asked again on their own, over a grade book held.
                payload.gradeBook.examsSubscribed = counters.num_iscriz ?? 0
                payload.gradeBook.examsGiven = counters.num_esiti ?? 0
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

    /// What the target call said: a target, or that none is set.
    private struct TargetAnswer: Sendable {
        var value: Double?
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
    /// - Returns: The answer, whose value is `nil` when no target is set, or `nil`
    ///   when the call failed.
    private static func target(matricola: String, _ env: Env) async -> TargetAnswer? {
        await attempt("Target average", nil) {
            let data = try await env.http.data(
                for: APIRequest(host: .libretto, path: "/mediaobiettivo/\(matricola)"))
            #if DEBUG
            log.notice("mediaobiettivo shape: \(JSONShape.describe(data), privacy: .public)")
            #endif
            let value = try await BackgroundJSON.decode(JSONValue.self, from: data)
            let fields = value.objectValue ?? value.arrayValue?.first?.objectValue
            return TargetAnswer(value: fields?.firstValue([
                "media", "media_obiettivo", "mediaObiettivo", "valore", "target",
            ])?.doubleValue)
        }
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
