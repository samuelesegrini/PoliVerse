import Foundation

/// A member of teaching staff, assembled from what the app already knows.
///
/// There is no public staff directory to search: the structure endpoint needs a
/// token and a person id the app never sees, and the service map carries no
/// name-to-id lookup. So the roster is built from the places a lecturer's name does
/// appear — the course list and the exam sittings — which finds the people who teach
/// this student.
nonisolated struct Teacher: Identifiable, Sendable, Hashable {
    /// The lower-cased name, which is all that identifies a lecturer here.
    var id: String { name.lowercased() }
    /// The lecturer's name, normalised by ``normalise(_:)``.
    let name: String
    /// Their address, where a course carried one.
    let email: String?
    /// Courses of theirs the student is enrolled in. Empty for a lecturer known only from an exam sitting.
    let courses: [Course]

    /// Builds the roster from the course list and the exam sittings.
    ///
    /// Names are normalised before grouping, since they arrive upper-cased from the
    /// exams endpoint and title-cased elsewhere and would otherwise produce the same
    /// person twice. The first address found for a name is kept.
    ///
    /// - Parameters:
    ///   - courses: The enrolled teachings.
    ///   - sessions: The exam sittings.
    /// - Returns: The lecturers, sorted by name.
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

    /// Trims and title-cases a lecturer's name, rejecting the placeholders the
    /// endpoints use for “no lecturer recorded”.
    ///
    /// - Parameter raw: The name as an endpoint sends it.
    /// - Returns: The name, or `nil` for `nil`, for two characters or fewer, or for a
    ///   dash. An upper-cased name is title-cased by ``Course/normalise(_:)``.
    static func normalise(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2, trimmed != "—", trimmed != "-" else { return nil }
        // Shouted upstream; the same casing rule as course names.
        return trimmed == trimmed.uppercased() ? Course.normalise(trimmed) : trimmed
    }

    /// Whether a query appears in this lecturer's name or address.
    ///
    /// - Parameter query: What the student typed.
    /// - Returns: `true` on a case-insensitive substring match.
    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || (email ?? "").localizedCaseInsensitiveContains(query)
    }
}
