import Foundation
import OSLog

/// The Moodle REST client for WeBeep.
///
/// Every call is a `GET /webservice/rest/server.php` carrying `wstoken`, `wsfunction`
/// and `moodlewsrestformat=json`.
///
/// - Important: Moodle reports failures with HTTP 200 and an error object in the body.
///   Checking the status alone would decode an error as an empty result and show an
///   empty course list instead of an expired session, so every response is checked for
///   ``MoodleError`` before the expected shape is decoded.
nonisolated final class WeBeepAPI: Sendable {
    /// What can go wrong with a WeBeep call.
    enum Failure: LocalizedError {
        /// Moodle refused the call, with its own code and message.
        case moodle(code: String, message: String)
        /// The request never completed.
        case transport(any Error)
        /// The response arrived but would not decode into the expected shape.
        case decoding(any Error)

        /// The localised sentence shown to the student. An invalid token is reported as an
        /// expired session; any other Moodle refusal is reported in Moodle's own words.
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

        /// Whether the token is dead and the student must sign in to WeBeep again.
        ///
        /// `true` for Moodle's `invalidtoken`, `accessexception` and `invalidlogin`.
        var isAuthFailure: Bool {
            if case .moodle(let code, _) = self {
                return ["invalidtoken", "accessexception", "invalidlogin"].contains(code)
            }
            return false
        }
    }

    /// The web-service token every call carries.
    private let token: String
    /// The session requests are issued through.
    private let session: URLSession
    /// Diagnostic log for this type, under the `webeep` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "webeep")

    /// Creates the client.
    ///
    /// - Parameters:
    ///   - token: The web-service token from ``WeBeepAuth``.
    ///   - session: The session requests are issued through.
    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Performs one web-service call and decodes its response off the main actor.
    ///
    /// - Parameters:
    ///   - function: The `wsfunction` to call.
    ///   - parameters: Extra query items, in whichever array form Moodle expects.
    ///   - type: The shape to decode.
    /// - Returns: The decoded response.
    /// - Throws: ``Failure``.
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

    /// Reads the signed-in user's own Moodle id, which the course list requires.
    ///
    /// - Returns: The site information.
    /// - Throws: ``Failure``.
    func siteInfo() async throws -> MoodleSiteInfo {
        try await call("core_webservice_get_site_info", as: MoodleSiteInfo.self)
    }

    /// The student's enrolled courses, with their favourite and hidden flags.
    ///
    /// - Parameter userID: The Moodle user id from ``siteInfo()``.
    /// - Returns: The courses.
    /// - Throws: ``Failure``.
    func courses(userID: Int) async throws -> [MoodleCourse] {
        try await call(
            "core_enrol_get_users_courses",
            parameters: ["userid": String(userID)],
            as: [MoodleCourse].self
        )
    }

    /// A forum's first page of discussions.
    ///
    /// In Moodle's default order: pinned first, then by last activity rather than by
    /// creation — which is why ``AnnouncementDetector`` reads each post's creation time.
    ///
    /// - Parameters:
    ///   - forumID: The forum instance.
    ///   - perPage: How many discussions to ask for.
    /// - Returns: The discussions.
    /// - Throws: ``Failure``.
    func discussions(forumID: Int, perPage: Int = 10) async throws -> [MoodleDiscussion] {
        try await call(
            "mod_forum_get_forum_discussions",
            parameters: ["forumid": String(forumID), "page": "0", "perpage": String(perPage)],
            as: MoodleDiscussions.self
        ).discussions ?? []
    }

    /// The lecturers listed on several courses, in one request.
    ///
    /// - Parameter courseIDs: Moodle's course ids.
    /// - Returns: The staff names by course id.
    /// - Throws: ``Failure``.
    func contacts(courseIDs: [Int]) async throws -> [Int: [String]] {
        let response = try await call("core_course_get_courses_by_field",
                                      parameters: ["field": "ids", "value": courseIDs.map(String.init).joined(separator: ",")],
                                      as: MoodleCoursesByField.self)
        return Dictionary((response.courses ?? []).map { ($0.id, ($0.contacts ?? []).compactMap(\.fullname)) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// The enrolment instances a course offers, which say whether it takes
    /// self-enrolment.
    ///
    /// - Parameter courseID: Moodle's course id.
    /// - Returns: The enrolment methods.
    /// - Throws: ``Failure``.
    func enrolmentMethods(courseID: Int) async throws -> [MoodleEnrolmentMethod] {
        try await call("core_enrol_get_course_enrolment_methods",
                       parameters: ["courseid": String(courseID)], as: [MoodleEnrolmentMethod].self)
    }

    /// One thread: its opening post and every reply, oldest first.
    ///
    /// - Parameter discussionID: The discussion's id.
    /// - Returns: The posts.
    /// - Throws: ``Failure``.
    func discussionPosts(discussionID: Int) async throws -> MoodlePosts {
        try await call(
            "mod_forum_get_discussion_posts",
            parameters: ["discussionid": String(discussionID), "sortby": "created", "sortdirection": "ASC"],
            as: MoodlePosts.self)
    }

    /// Every assignment of several courses, in one request.
    ///
    /// - Parameter courseIDs: Moodle's course ids.
    /// - Returns: The assignments by course id.
    /// - Throws: ``Failure``.
    func assignments(courseIDs: [Int]) async throws -> [Int: [MoodleAssignment]] {
        var parameters: [String: String] = [:]
        for (index, id) in courseIDs.enumerated() { parameters["courseids[\(index)]"] = String(id) }
        let response = try await call("mod_assign_get_assignments", parameters: parameters,
                                      as: MoodleAssignmentsResponse.self)
        return Dictionary((response.courses ?? []).map { ($0.id, $0.assignments ?? []) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// A course page's sections, with the modules and files in each.
    ///
    /// - Parameter courseID: Moodle's course id.
    /// - Returns: The sections.
    /// - Throws: ``Failure``.
    func contents(courseID: Int) async throws -> [MoodleSection] {
        try await call(
            "core_course_get_contents",
            parameters: ["courseid": String(courseID)],
            as: [MoodleSection].self
        )
    }

    /// Stars or unstars a course on WeBeep.
    ///
    /// - Parameters:
    ///   - courseID: Moodle's course id.
    ///   - favourite: The value to set.
    /// - Throws: ``Failure``.
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

    /// Hides or reveals a course on WeBeep.
    ///
    /// Moodle has no dedicated call: “Remove from view” is a user preference, which
    /// `core_enrol_get_users_courses` reads back as `hidden`. Revealing a course unsets
    /// the preference by sending no value — setting it to `0` would leave it present.
    ///
    /// - Parameters:
    ///   - courseID: Moodle's course id.
    ///   - hidden: The value to set.
    /// - Throws: ``Failure``.
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

    /// A file address with the web-service token attached.
    ///
    /// Moodle's file addresses are not public and take the token on the query string, so
    /// the token ends up in the URL of every download. That is how Moodle works, and it is
    /// the reason these addresses are neither logged nor handed to anything outside the
    /// app — see ``FileDownloadModel``.
    ///
    /// Any existing `token` or `forcedownload` item is replaced.
    ///
    /// - Parameter fileURL: The address as Moodle sent it.
    /// - Returns: The authenticated address, or `nil` when the input is not a URL.
    func authenticatedFileURL(_ fileURL: String) -> URL? {
        guard var components = URLComponents(string: fileURL) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "token" || $0.name == "forcedownload" }
        items.append(.init(name: "token", value: token))
        components.queryItems = items
        return components.url
    }
}
