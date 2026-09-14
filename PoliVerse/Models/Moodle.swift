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
///
/// Moodle already tracks the three states the My Courses page offers —
/// favourite, hidden, and neither — so they are read from it rather than kept
/// locally. `isfavourite` is a real favourite record; `hidden` is the user
/// preference `block_myoverview_hidden_course_{id}`, which the same endpoint
/// resolves for us (`enrol/externallib.php`, line ~394).
nonisolated struct MoodleCourse: Decodable, Sendable {
    let id: Int
    let fullname: String
    let shortname: String?
    /// Epoch seconds. Used to derive the academic year a course belongs to.
    let startdate: Int?
    let enddate: Int?
    let isfavourite: Bool?
    let hidden: Bool?

    /// Copies with the flag changed, so a successful write is reflected without
    /// a refetch.
    func withFavourite(_ value: Bool) -> MoodleCourse {
        MoodleCourse(id: id, fullname: fullname, shortname: shortname,
                     startdate: startdate, enddate: enddate,
                     isfavourite: value, hidden: hidden)
    }

    func withHidden(_ value: Bool) -> MoodleCourse {
        MoodleCourse(id: id, fullname: fullname, shortname: shortname,
                     startdate: startdate, enddate: enddate,
                     isfavourite: isfavourite, hidden: value)
    }
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
    /// The activity's own id — what `mod_forum_*` calls a forum id.
    var instance: Int? = nil
}

nonisolated struct MoodleContent: Decodable, Sendable {
    let type: String?
    let filename: String?
    /// The folder inside the module, `/` at its root. Two files of a folder
    /// module can share a name in different subfolders.
    var filepath: String? = nil
    let filesize: Int?
    let fileurl: String?
    let timemodified: Int?
    let mimetype: String?
}

/// `mod_forum_get_forum_discussions` — one discussion's first post.
///
/// Field names from `mod/forum/externallib.php` (MOODLE_405_STABLE,
/// `get_forum_discussions_returns`). Everything optional but the id: a field
/// missing on WeBeep must not cost the whole list.
nonisolated struct MoodleDiscussion: Decodable, Sendable, Equatable {
    let id: Int
    let discussion: Int?
    let name: String?
    let subject: String?
    let message: String?
    let created: Int?
    let timemodified: Int?
    let userfullname: String?
    let pinned: Bool?

    var title: String { subject ?? name ?? "" }
}

nonisolated struct MoodleDiscussions: Decodable, Sendable {
    let discussions: [MoodleDiscussion]?
}

/// `mod_assign_get_assignments` — assignments per course.
///
/// Field names from `mod/assign/externallib.php` (MOODLE_405_STABLE,
/// `get_assignments_assignment_structure`). A `duedate` of 0 means none.
nonisolated struct MoodleAssignment: Decodable, Sendable, Equatable {
    let id: Int
    let name: String?
    let duedate: Int?

    var due: Date? {
        guard let duedate, duedate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(duedate))
    }
}

nonisolated struct MoodleAssignmentsResponse: Decodable, Sendable {
    struct CourseAssignments: Decodable, Sendable {
        let id: Int
        let assignments: [MoodleAssignment]?
    }
    let courses: [CourseAssignments]?
}

/// Moodle answers errors with HTTP 200 and an error body, so every response has
/// to be sniffed for this before decoding the shape we wanted.
nonisolated struct MoodleError: Decodable, Sendable {
    let exception: String?
    let errorcode: String?
    let message: String?
}


/// What Moodle returns from a write that has nothing else to say.
///
/// These calls answer with `{"warnings": []}` or with `null`, so the response
/// is decoded leniently rather than treated as a failure when it is empty.
nonisolated struct MoodleWarnings: Decodable, Sendable {
    struct Warning: Decodable, Sendable {
        let item: String?
        let warningcode: String?
        let message: String?
    }

    let warnings: [Warning]?

    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        warnings = try? container?.decodeIfPresent([Warning].self, forKey: .warnings)
    }

    private enum CodingKeys: String, CodingKey { case warnings }
}
