import Foundation

/// `core_webservice_get_site_info` — the only way to learn our own user id,
/// which `core_enrol_get_users_courses` requires.
nonisolated struct MoodleSiteInfo: Decodable, Sendable {
    let userid: Int
    let username: String?
    let fullname: String?
    let sitename: String?
}

/// `core_enrol_get_users_courses`
nonisolated struct MoodleCourse: Decodable, Sendable {
    let id: Int
    let fullname: String
    let shortname: String?
    let startdate: Int?
    let enddate: Int?
}

/// `core_course_get_contents` — a course is sections, each holding modules.
nonisolated struct MoodleSection: Decodable, Sendable {
    let id: Int
    let name: String
    let modules: [MoodleModule]?
}

nonisolated struct MoodleModule: Decodable, Sendable {
    let id: Int
    let name: String
    /// `resource`, `folder`, `url`, `forum`, `page`, `label`, …
    let modname: String
    let contents: [MoodleContent]?
}

nonisolated struct MoodleContent: Decodable, Sendable {
    let type: String?
    let filename: String?
    let filesize: Int?
    let fileurl: String?
    let timemodified: Int?
    let mimetype: String?
}

/// Moodle answers errors with HTTP 200 and an error body, so every response has
/// to be sniffed for this before decoding the shape we wanted.
nonisolated struct MoodleError: Decodable, Sendable {
    let exception: String?
    let errorcode: String?
    let message: String?
}
