import Foundation

/// The answer to `core_webservice_get_site_info`, which is the only way to learn the
/// signed-in user's own Moodle id — required by `core_enrol_get_users_courses`.
nonisolated struct MoodleSiteInfo: Decodable, Sendable {
    /// The signed-in user's Moodle id.
    let userid: Int
    /// Their Moodle username.
    let username: String?
    /// Their display name.
    let fullname: String?
    /// The Moodle site's name.
    let sitename: String?
}

/// One enrolled course, as `core_enrol_get_users_courses` sends it.
///
/// Moodle already tracks the three states the My Courses page offers — favourite,
/// hidden and neither — so they are read from here rather than kept locally.
/// ``isfavourite`` is a real favourite record and ``hidden`` is the user preference
/// the same endpoint resolves.
nonisolated struct MoodleCourse: Decodable, Sendable {
    /// Moodle's course id, which every other call is keyed by.
    let id: Int
    /// The course's title, which carries the teaching code and academic year — see
    /// ``Course/splitCode(from:)``.
    let fullname: String
    /// The course's short name.
    let shortname: String?
    /// When the course starts, in epoch seconds. Used to derive the academic year when
    /// the title does not carry one.
    let startdate: Int?
    /// When the course ends, in epoch seconds.
    let enddate: Int?
    /// Whether the course is starred.
    let isfavourite: Bool?
    /// Whether the course is removed from the student's own view.
    let hidden: Bool?
    /// The course's external id, set by the enrolment sync, which may carry the teaching
    /// code.
    var idnumber: String? = nil

    /// A copy with the favourite flag changed, so a successful write shows without a
    /// refetch.
    ///
    /// - Parameter value: The new flag.
    /// - Returns: The copy.
    func withFavourite(_ value: Bool) -> MoodleCourse {
        MoodleCourse(id: id, fullname: fullname, shortname: shortname,
                     startdate: startdate, enddate: enddate,
                     isfavourite: value, hidden: hidden, idnumber: idnumber)
    }

    /// A copy with the hidden flag changed, so a successful write shows without a
    /// refetch.
    ///
    /// - Parameter value: The new flag.
    /// - Returns: The copy.
    func withHidden(_ value: Bool) -> MoodleCourse {
        MoodleCourse(id: id, fullname: fullname, shortname: shortname,
                     startdate: startdate, enddate: enddate,
                     isfavourite: isfavourite, hidden: value, idnumber: idnumber)
    }
}

/// The answer to `core_course_get_courses_by_field`, read only for each course's
/// teaching contacts.
nonisolated struct MoodleCoursesByField: Decodable, Sendable {
    /// One course and the staff listed on it.
    nonisolated struct Course: Decodable, Sendable {
        /// One member of staff listed on a course.
        nonisolated struct Contact: Decodable, Sendable { let fullname: String? }
        /// Moodle's course id.
        let id: Int
        /// The staff listed on the course.
        let contacts: [Contact]?
    }
    /// The courses that were asked about.
    let courses: [Course]?
}

/// One enrolment instance a course offers, from
/// `core_enrol_get_course_enrolment_methods`.
///
/// Says what the course page allows, not how this student joined — which is what
/// ``EnrolmentOrigin`` uses it for.
nonisolated struct MoodleEnrolmentMethod: Decodable, Sendable {
    /// The enrolment instance's id.
    let id: Int
    /// The method's type, for example `self` or `manual`.
    let type: String
    /// The method's own name, where one is set.
    let name: String?
    /// Whether the method is enabled. Moodle's versions disagree on whether `status`
    /// arrives as a boolean or as `"1"`, so both are accepted.
    let isEnabled: Bool

    /// The four fields the endpoint sends. `status` is read by hand.
    private enum CodingKeys: String, CodingKey { case id, type, name, status }

    /// Decodes the method, accepting `status` as either a boolean or a string.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: A decoding error when `id` or `type` is missing. An unreadable `status`
    ///   is treated as disabled.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        if let flag = try? c.decode(Bool.self, forKey: .status) {
            isEnabled = flag
        } else {
            let text = (try? c.decode(String.self, forKey: .status)) ?? ""
            isEnabled = text == "1" || text.lowercased() == "true"
        }
    }

    /// Whether a course page takes self-enrolment.
    ///
    /// - Parameter methods: The course's enrolment instances.
    /// - Returns: `true` when an enabled `self` instance is present.
    static func allowsSelfEnrolment(_ methods: [MoodleEnrolmentMethod]) -> Bool {
        methods.contains { $0.type == "self" && $0.isEnabled }
    }
}

/// One section of a course, from `core_course_get_contents`. A course is sections,
/// each holding modules.
nonisolated struct MoodleSection: Decodable, Sendable {
    /// The section's id.
    let id: Int
    /// The section's name, as the course page shows it.
    let name: String
    /// The activities and resources in the section.
    let modules: [MoodleModule]?
}

/// One activity or resource within a section.
nonisolated struct MoodleModule: Decodable, Sendable {
    /// The course module's id.
    let id: Int
    /// The module's name on the course page.
    let name: String
    /// The module's kind: `resource`, `folder`, `url`, `forum`, `page`, `label` and so
    /// on.
    let modname: String
    /// The files and links the module holds.
    let contents: [MoodleContent]?
    /// The activity's own id, which is what the `mod_forum_*` calls mean by a forum id.
    /// Distinct from ``id``, the course module's.
    var instance: Int? = nil
}

/// One file or link inside a module.
nonisolated struct MoodleContent: Decodable, Sendable {
    /// What the entry is, usually `file` or `url`.
    let type: String?
    /// The file's name.
    let filename: String?
    /// The folder within the module, `/` at its root. Two files in one folder module can
    /// share a name in different subfolders.
    var filepath: String? = nil
    /// The file's size in bytes.
    let filesize: Int?
    /// Where to fetch the file. Needs the Moodle token appended.
    let fileurl: String?
    /// When the file last changed, in epoch seconds.
    let timemodified: Int?
    /// The file's media type, where Moodle records one.
    let mimetype: String?
}

/// One forum discussion's first post, from `mod_forum_get_forum_discussions`.
///
/// Everything but the id is optional: a field missing on WeBeep must not cost the
/// whole list.
nonisolated struct MoodleDiscussion: Decodable, Sendable, Equatable {
    /// The first post's id.
    let id: Int
    /// The discussion's own id, which `mod_forum_get_discussion_posts` takes.
    let discussion: Int?
    /// The discussion's name.
    let name: String?
    /// The first post's subject, preferred over ``name``.
    let subject: String?
    /// The first post's body, as an HTML fragment.
    let message: String?
    /// When the discussion was started, in epoch seconds.
    let created: Int?
    /// When it last changed, in epoch seconds.
    let timemodified: Int?
    /// Who started it.
    let userfullname: String?
    /// Whether the forum keeps it at the top.
    let pinned: Bool?

    /// The subject, falling back to the name and then to the empty string.
    var title: String { subject ?? name ?? "" }
}

/// Every post in one discussion, from `mod_forum_get_discussion_posts`.
nonisolated struct MoodlePosts: Decodable, Sendable {
    /// One post in a discussion.
    nonisolated struct Post: Decodable, Sendable, Identifiable {
        /// Who wrote a post.
        nonisolated struct Author: Decodable, Sendable {
            /// The author's display name.
            let fullname: String?
        }
        /// The post's id.
        let id: Int
        /// The post's subject.
        let subject: String?
        /// The post's body, as an HTML fragment.
        let message: String?
        /// When the post was written, in epoch seconds.
        let timecreated: Int?
        /// Whether the post replies to another.
        let hasparent: Bool?
        /// Who wrote it.
        let author: Author?

        /// Whether the post replies to another. `false` when Moodle does not say.
        var isReply: Bool { hasparent ?? false }
        /// When the post was written, or `nil` when Moodle does not say.
        var created: Date? { timecreated.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    }
    /// The posts, newest first, as Moodle orders them.
    let posts: [Post]?

    /// The posts oldest first, which is how a thread reads. Ties are broken by id.
    var chronological: [Post] {
        (posts ?? []).sorted { ($0.timecreated ?? 0, $0.id) < ($1.timecreated ?? 0, $1.id) }
    }
}

/// The answer to `mod_forum_get_forum_discussions`.
nonisolated struct MoodleDiscussions: Decodable, Sendable {
    /// The forum's discussions.
    let discussions: [MoodleDiscussion]?
}

/// One assignment, from `mod_assign_get_assignments`.
nonisolated struct MoodleAssignment: Decodable, Sendable, Equatable {
    /// The assignment's id.
    let id: Int
    /// The assignment's name.
    let name: String?
    /// When it is due, in epoch seconds. Zero means no deadline is set.
    let duedate: Int?

    /// The deadline, or `nil` when none is set.
    var due: Date? {
        guard let duedate, duedate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(duedate))
    }
}

/// The answer to `mod_assign_get_assignments`.
nonisolated struct MoodleAssignmentsResponse: Decodable, Sendable {
    /// One course's assignments.
    struct CourseAssignments: Decodable, Sendable {
        /// Moodle's course id.
        let id: Int
        /// The course's assignments.
        let assignments: [MoodleAssignment]?
    }
    /// The courses that were asked about.
    let courses: [CourseAssignments]?
}

/// Moodle's error body.
///
/// Moodle answers errors with HTTP 200 and this shape, so every response has to be
/// checked for it before the expected shape is decoded.
nonisolated struct MoodleError: Decodable, Sendable {
    /// The exception class Moodle raised.
    let exception: String?
    /// Moodle's own error code, for example `invalidtoken`.
    let errorcode: String?
    /// The error in words.
    let message: String?
}


/// What Moodle returns from a write that has nothing else to say.
///
/// These calls answer `{"warnings": []}` or `null`, so the body is decoded leniently
/// rather than treated as a failure when it is empty.
nonisolated struct MoodleWarnings: Decodable, Sendable {
    /// One warning from a write.
    struct Warning: Decodable, Sendable {
        /// What the warning is about.
        let item: String?
        /// Moodle's own warning code.
        let warningcode: String?
        /// The warning in words.
        let message: String?
    }

    /// The warnings, or `nil` when the body carried none.
    let warnings: [Warning]?

    /// Decodes the warnings if there are any, and succeeds either way.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Never.
    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        warnings = try? container?.decodeIfPresent([Warning].self, forKey: .warnings)
    }

    /// The only key these bodies carry, and it may be absent.
    private enum CodingKeys: String, CodingKey { case warnings }
}
