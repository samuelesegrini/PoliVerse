import Foundation

/// A member of teaching staff, assembled from what the app already knows.
///
/// There is no public directory to search: `maps_rest /struttura/{personaId}`
/// needs a token *and* a person id the app never sees, and there is no
/// name-to-id lookup anywhere in the service map. So this is built from the
/// places a teacher's name genuinely appears — the course list and the exam
/// sittings — rather than from an endpoint that does not exist.
///
/// That is a smaller thing than a staff directory, and honest about it: it
/// finds the people who teach *you*, which is what a student searching by name
/// almost always wants.
nonisolated struct Teacher: Identifiable, Sendable, Hashable {
    /// The normalised name, which is all that reliably identifies them here.
    var id: String { name.lowercased() }
    let name: String
    let email: String?
    /// Courses of theirs the student is enrolled in.
    let courses: [Course]

    /// Builds the roster from courses and exam sittings.
    ///
    /// Names arrive shouted from `/v1/insegn` and title-cased elsewhere, so
    /// they are normalised before grouping or the same person appears twice.
    static func roster(courses: [Course], sessions: [ExamSession]) -> [Teacher] {
        var byName: [String: (name: String, email: String?, courses: [Course])] = [:]

        func add(_ raw: String?, email: String?, course: Course?) {
            guard let cleaned = Teacher.normalise(raw) else { return }
            var entry = byName[cleaned.lowercased()] ?? (cleaned, nil, [])
            entry.email = entry.email ?? email
            if let course, !entry.courses.contains(where: { $0.id == course.id }) {
                entry.courses.append(course)
            }
            byName[cleaned.lowercased()] = entry
        }

        for course in courses {
            add(course.teacher, email: course.teacherEmail, course: course)
        }
        for session in sessions {
            add(session.teacher, email: nil, course: nil)
        }

        return byName.values
            .map { Teacher(name: $0.name, email: $0.email, courses: $0.courses) }
            .sorted { $0.name < $1.name }
    }

    /// Rejects the placeholders the endpoints use for "no teacher recorded",
    /// which would otherwise become a person called "—".
    static func normalise(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2, trimmed != "—", trimmed != "-" else { return nil }
        // Shouted upstream; the same casing rule as course names.
        return trimmed == trimmed.uppercased() ? Course.normalise(trimmed) : trimmed
    }

    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || (email ?? "").localizedCaseInsensitiveContains(query)
    }
}
