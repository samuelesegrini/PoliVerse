import Foundation

/// A forum on a course's WeBeep page: the teacher's announcements, or a
/// discussion forum students write in.
nonisolated struct CourseForum: Identifiable, Sendable, Hashable {
    nonisolated enum Kind: Sendable, Hashable {
        case announcements, discussion
    }

    /// The forum instance — what `mod_forum_*` calls a forum id.
    let id: Int
    let name: String
    let kind: Kind

    /// Every forum on the page, announcements first, otherwise in page order.
    static func forums(in sections: [MoodleSection]) -> [CourseForum] {
        let all = sections.flatMap { $0.modules ?? [] }.compactMap { module -> CourseForum? in
            guard module.modname == "forum", let instance = module.instance else { return nil }
            return CourseForum(id: instance, name: module.name,
                               kind: isAnnouncements(module.name) ? .announcements : .discussion)
        }
        return all.filter { $0.kind == .announcements } + all.filter { $0.kind == .discussion }
    }

    /// Moodle creates one per course ("Annunci", "Announcements", "Avvisi",
    /// "News forum").
    static func isAnnouncements(_ name: String) -> Bool {
        DocumentClassifier.normalise(name).range(
            of: #"\b(annunci|avvisi|announcements?|news forum)\b"#, options: .regularExpression) != nil
    }
}
