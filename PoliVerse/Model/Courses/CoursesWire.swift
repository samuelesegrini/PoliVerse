import Foundation

// The shape `/rest/v1/insegn` sends for a teaching.

/// One teaching as `/rest/v1/insegn` sends it, on the exam-registration host.
///
/// One response carries both the course list and every exam sitting, so
/// ``CourseModel`` and ``CareerModel`` share a single fetch rather than calling the
/// endpoint twice.
///
/// Every field is optional: one unexpected null in one teaching would otherwise fail
/// the whole array and produce an empty course list, which looks from the interface
/// exactly like having no courses.
nonisolated struct TeachingDTO: Decodable, Sendable {
    /// The teaching's code within the study plan.
    let c_insegn_piano: String?
    /// The class code, used as the identifier when the plan code is absent.
    let c_classe_m: Int?
    /// The teaching's name, upper-cased upstream.
    let xdescrizione: String?
    /// The examining lecturer's name.
    let docente_esame: String?
    /// The examining lecturer's address.
    let docente_esame_mail: String?
    /// The academic year of attendance.
    let aa_freq: String?
    /// The semester of attendance.
    let semestre_freq: String?
    /// The exam sittings for this teaching.
    let appelliEsame: [ExamDTO]?

    /// The teaching's identifier: the plan code, falling back to the class code.
    ///
    /// `nil` when neither is present, in which case the teaching is unusable.
    var identifier: String? {
        if let c_insegn_piano, !c_insegn_piano.isEmpty { return c_insegn_piano }
        return c_classe_m.map(String.init)
    }

    /// Converts the payload into a ``Course``.
    ///
    /// Credits are left at zero, since this endpoint does not carry them; the study plan
    /// supplies them.
    ///
    /// - Returns: The course, or `nil` without an ``identifier`` or a name.
    func toCourse() -> Course? {
        guard let identifier, let xdescrizione, !xdescrizione.isEmpty else { return nil }
        return Course(
            id: identifier,
            name: Course.normalise(xdescrizione),
            teacher: docente_esame?.capitalized ?? "—",
            cfu: 0, // not present on this endpoint; filled from the study plan
            semester: semestre_freq ?? "—",
            academicYear: aa_freq ?? "—",
            teacherEmail: docente_esame_mail
        )
    }

    /// Converts this teaching's sittings into ``ExamSession`` values, stamping each with
    /// the teaching's name, code and lecturer.
    ///
    /// - Returns: The sittings, or an empty array without an ``identifier``.
    func toExamSessions() -> [ExamSession] {
        guard let identifier else { return [] }
        return (appelliEsame ?? []).map {
            $0.toSession(
                courseName: xdescrizione ?? "—",
                courseCode: identifier,
                teacher: docente_esame
            )
        }
    }
}

/// The answer to `/rest/v1/insegn`.
nonisolated struct TeachingsResponse: Decodable, Sendable {
    /// The teachings, under the key the endpoint uses.
    let INSEGN: [TeachingDTO]?

    /// ``INSEGN``, or an empty array.
    var teachings: [TeachingDTO] { INSEGN ?? [] }
}
