import Foundation
import OSLog

/// The ``Source`` for the student's enrolled teachings.
///
/// WeBeep is asked first and `/v1/insegn` is the fallback. `/v1/insegn` is the exam
/// registration endpoint, so it lists teachings that still have sittings to sit: a
/// student who has passed everything gets an empty array from it, which is correct
/// for exams and useless as a course list. WeBeep lists actual enrolments and keeps
/// them after the exam is passed.
nonisolated struct CourseSource: Source {
    /// Names the offline record and the log category.
    static let id = "courses"
    /// Fifteen minutes: the enrolled-course list changes at most once a semester.
    static let ttl: TimeInterval = 900

    /// Diagnostic log for this type, under the `courses` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "courses")

    /// Reads the WeBeep enrolments.
    ///
    /// A closure over ``CourseEnrolments`` rather than the conformer itself, because the
    /// protocol is main-actor bound while the fetch is not, and the ownership belongs to
    /// the call site.
    let enrolled: @Sendable @MainActor () async -> [Course]

    /// Fetches the enrolled teachings, preferring WeBeep.
    ///
    /// - Parameter env: The transport for the fallback request.
    /// - Returns: The WeBeep enrolments, or the teachings from `/v1/insegn` when WeBeep
    ///   has none.
    /// - Throws: ``APIError`` from the fallback request.
    func fetch(_ env: Env) async throws -> [Course] {
        let webeep = await enrolled()
        if !webeep.isEmpty {
            Self.log.notice("WeBeep provided \(webeep.count, privacy: .public) enrolled courses")
            return webeep
        }

        let data = try await env.http.data(for: APIRequest(
            host: .iae,
            path: "/v1/insegn",
            query: [.init(name: "lang", value: PoliMiLanguage.current.rawValue)]
        ))
        let response = try await BackgroundJSON.decode(TeachingsResponse.self, from: data,
                                                       iso8601Dates: true)
        let loaded = response.teachings.compactMap { $0.toCourse() }
        Self.log.notice("insegn returned \(response.teachings.count, privacy: .public) teachings, \(loaded.count, privacy: .public) usable")
        return loaded
    }

    /// The sample course list.
    func sample() -> [Course] { Course.samples }
}
