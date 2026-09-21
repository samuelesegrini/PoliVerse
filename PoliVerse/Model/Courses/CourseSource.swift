import Foundation
import OSLog

/// The student's enrolled teachings, from whichever service actually knows
/// them.
///
/// ## Why WeBeep leads
///
/// `/v1/insegn` is the *exam registration* endpoint — `iae` is iscrizione
/// appelli esami — so it lists teachings that still have sittings to sit. A
/// student who has passed everything gets an empty array from it, which is
/// correct for exams and useless as a course list. WeBeep lists actual
/// enrolments and keeps them after the exam is passed, so it is asked first and
/// `/v1/insegn` is the fallback for an account that has not connected it.
nonisolated struct CourseSource: Source {
    static let id = "courses"
    /// Fifteen minutes: the enrolled-course list changes at most once a
    /// semester.
    static let ttl: TimeInterval = 900

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "courses")

    /// Where the better answer comes from.
    ///
    /// A closure over ``CourseEnrolments`` rather than the conformer itself:
    /// the protocol is main-actor bound and this runs off it, and the weak
    /// capture belongs at the call site that knows the ownership.
    let enrolled: @Sendable @MainActor () async -> [Course]

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

    func sample() -> [Course] { Course.samples }
}
