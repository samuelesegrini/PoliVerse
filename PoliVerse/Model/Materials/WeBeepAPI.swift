import Foundation
import OSLog

/// Moodle REST client for WeBeep.
///
/// Every call is `GET /webservice/rest/server.php` with `wstoken`, `wsfunction`
/// and `moodlewsrestformat=json`.
///
/// - Important: Moodle reports failures with **HTTP 200** and an error object
///   in the body. Checking the status code alone would decode an error as an
///   empty result and show the user an empty course list instead of "session
///   expired", so every response is sniffed for an error shape first.
nonisolated final class WeBeepAPI: Sendable {
    enum Failure: LocalizedError {
        case moodle(code: String, message: String)
        case transport(any Error)
        case decoding(any Error)

        var errorDescription: String? {
            switch self {
            case .moodle(let code, let message):
                code == "invalidtoken"
                    ? "La sessione WeBeep è scaduta. Accedi di nuovo."
                    : message
            case .transport: "Connessione a WeBeep non riuscita."
            case .decoding: "Risposta di WeBeep non leggibile."
            }
        }

        /// True when the token is dead and the user must log in again.
        var isAuthFailure: Bool {
            if case .moodle(let code, _) = self {
                return ["invalidtoken", "accessexception", "invalidlogin"].contains(code)
            }
            return false
        }
    }

    private let token: String
    private let session: URLSession
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "webeep")

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func call<T: Decodable & Sendable>(
        _ function: String,
        parameters: [String: String] = [:],
        as type: T.Type
    ) async throws -> T {
        var components = URLComponents(
            string: "\(WeBeepAuth.siteURL)/webservice/rest/server.php")!
        components.queryItems = [
            .init(name: "wstoken", value: token),
            .init(name: "wsfunction", value: function),
            .init(name: "moodlewsrestformat", value: "json"),
        ] + parameters.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error)
        }

        // Errors arrive as HTTP 200. Sniff before decoding.
        if let error = try? await BackgroundJSON.decode(MoodleError.self, from: data),
           let code = error.errorcode {
            log.error("Moodle \(function) failed: \(code)")
            throw Failure.moodle(code: code, message: error.message ?? "Errore WeBeep.")
        }

        do {
            return try await BackgroundJSON.decode(T.self, from: data)
        } catch {
            log.error("Decoding \(function) failed: \(error)")
            throw Failure.decoding(error)
        }
    }

    func siteInfo() async throws -> MoodleSiteInfo {
        try await call("core_webservice_get_site_info", as: MoodleSiteInfo.self)
    }

    func courses(userID: Int) async throws -> [MoodleCourse] {
        try await call(
            "core_enrol_get_users_courses",
            parameters: ["userid": String(userID)],
            as: [MoodleCourse].self
        )
    }

    /// `mod_forum_get_forum_discussions` — a forum's first page of
    /// discussions, in Moodle's default order: pinned first, then by last
    /// activity. Not by creation — which is why the detector reads `created`.
    func discussions(forumID: Int, perPage: Int = 10) async throws -> [MoodleDiscussion] {
        try await call(
            "mod_forum_get_forum_discussions",
            parameters: ["forumid": String(forumID), "page": "0", "perpage": String(perPage)],
            as: MoodleDiscussions.self
        ).discussions ?? []
    }

    /// `core_course_get_courses_by_field` with `field=ids`: the courses'
    /// contacts — their lecturers — in one request.
    func contacts(courseIDs: [Int]) async throws -> [Int: [String]] {
        let response = try await call("core_course_get_courses_by_field",
                                      parameters: ["field": "ids", "value": courseIDs.map(String.init).joined(separator: ",")],
                                      as: MoodleCoursesByField.self)
        return Dictionary((response.courses ?? []).map { ($0.id, ($0.contacts ?? []).compactMap(\.fullname)) },
                          uniquingKeysWith: { first, _ in first })
    }

    func enrolmentMethods(courseID: Int) async throws -> [MoodleEnrolmentMethod] {
        try await call("core_enrol_get_course_enrolment_methods",
                       parameters: ["courseid": String(courseID)], as: [MoodleEnrolmentMethod].self)
    }

    /// `mod_forum_get_discussion_posts` — one thread, opening post and replies.
    func discussionPosts(discussionID: Int) async throws -> MoodlePosts {
        try await call(
            "mod_forum_get_discussion_posts",
            parameters: ["discussionid": String(discussionID), "sortby": "created", "sortdirection": "ASC"],
            as: MoodlePosts.self)
    }

    /// `mod_assign_get_assignments` — every assignment of the given courses in
    /// one request, `courseids[n]` as Moodle's array form expects.
    func assignments(courseIDs: [Int]) async throws -> [Int: [MoodleAssignment]] {
        var parameters: [String: String] = [:]
        for (index, id) in courseIDs.enumerated() { parameters["courseids[\(index)]"] = String(id) }
        let response = try await call("mod_assign_get_assignments", parameters: parameters,
                                      as: MoodleAssignmentsResponse.self)
        return Dictionary((response.courses ?? []).map { ($0.id, $0.assignments ?? []) },
                          uniquingKeysWith: { first, _ in first })
    }

    func contents(courseID: Int) async throws -> [MoodleSection] {
        try await call(
            "core_course_get_contents",
            parameters: ["courseid": String(courseID)],
            as: [MoodleSection].self
        )
    }

    /// `core_course_set_favourite_courses`
    ///
    /// Parameters are the bracketed array form Moodle expects:
    /// `courses[0][id]` and `courses[0][favourite]`
    /// (`course/externallib.php`, `set_favourite_courses_parameters`).
    func setFavourite(courseID: Int, favourite: Bool) async throws {
        _ = try await call(
            "core_course_set_favourite_courses",
            parameters: [
                "courses[0][id]": String(courseID),
                "courses[0][favourite]": favourite ? "1" : "0",
            ],
            as: MoodleWarnings.self
        )
    }

    /// Hides or unhides a course.
    ///
    /// Moodle has no dedicated call for this: "Remove from view" is a user
    /// preference, `block_myoverview_hidden_course_{id}`, which
    /// `core_enrol_get_users_courses` reads back as `hidden`.
    ///
    /// Sending no `value` unsets the preference, which is how a course is
    /// un-hidden — setting it to `0` would leave the preference present.
    func setHidden(courseID: Int, hidden: Bool) async throws {
        var parameters = [
            "preferences[0][type]": "block_myoverview_hidden_course_\(courseID)"
        ]
        if hidden { parameters["preferences[0][value]"] = "1" }

        _ = try await call(
            "core_user_update_user_preferences",
            parameters: parameters,
            as: MoodleWarnings.self
        )
    }

    /// Moodle file URLs are not public — the token goes on the query string.
    ///
    /// That means the token ends up in the URL of every download. Acceptable
    /// because it is how Moodle works, but a reason not to log these URLs or
    /// hand them to anything outside the app.
    func authenticatedFileURL(_ fileURL: String) -> URL? {
        guard var components = URLComponents(string: fileURL) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "token" || $0.name == "forcedownload" }
        items.append(.init(name: "token", value: token))
        components.queryItems = items
        return components.url
    }
}
