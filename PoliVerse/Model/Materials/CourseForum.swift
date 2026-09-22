import Foundation

/// A forum on a course's WeBeep page: the lecturer's announcements, or a discussion
/// forum students write in.
///
/// Read only, by decision rather than by omission: the app never posts, and the
/// reasons are in `docs/writes-to-university-systems.md`. The short form is
/// that an `announcements` forum is staff-only anyway, and a post in a
/// discussion forum carries the student's name in front of the whole course and
/// cannot be taken back from here.
nonisolated struct CourseForum: Identifiable, Sendable, Hashable {
    /// What a forum is for.
    nonisolated enum Kind: Sendable, Hashable {
        /// `announcements` for the forum Moodle creates per course, which only staff post in;
        /// `discussion` for any other.
        case announcements, discussion
    }

    /// The forum instance, which is what the `mod_forum_*` calls mean by a forum id.
    let id: Int
    /// The forum's name on the course page.
    let name: String
    /// What the forum is for.
    let kind: Kind

    /// Every forum on a course page.
    ///
    /// - Parameter sections: The course's contents.
    /// - Returns: The forums, announcements first and the rest in page order. Forum
    ///   modules without an instance id are skipped.
    static func forums(in sections: [MoodleSection]) -> [CourseForum] {
        let all = sections.flatMap { $0.modules ?? [] }.compactMap { module -> CourseForum? in
            guard module.modname == "forum", let instance = module.instance else { return nil }
            return CourseForum(id: instance, name: module.name,
                               kind: isAnnouncements(module.name) ? .announcements : .discussion)
        }
        return all.filter { $0.kind == .announcements } + all.filter { $0.kind == .discussion }
    }

    /// Whether a forum's name is the one Moodle creates per course.
    ///
    /// - Parameter name: The forum's name.
    /// - Returns: `true` for “Annunci”, “Avvisi”, “Announcements” or “News forum”,
    ///   matched case- and accent-insensitively.
    static func isAnnouncements(_ name: String) -> Bool {
        DocumentClassifier.normalise(name).range(
            of: #"\b(annunci|avvisi|announcements?|news forum)\b"#, options: .regularExpression) != nil
    }
}
