import Foundation

/// The shape `/rest/v1/insegn` sends for a teaching.

/// Wire shape of an entry in `/rest/v1/insegn` (the `iae` exams host).
///
/// One response carries both the course list and every exam sitting, so
/// `CourseModel` and `CareerModel` share a single fetch rather than
/// hitting the endpoint twice.
/// Everything is optional.
///
/// A single unexpected null in one teaching would otherwise fail the whole
/// array and produce an empty course list — indistinguishable, from the UI,
/// from having no courses.
nonisolated struct TeachingDTO: Decodable, Sendable {
    let c_insegn_piano: String?
    let c_classe_m: Int?
    let xdescrizione: String?
    let docente_esame: String?
    let docente_esame_mail: String?
    let aa_freq: String?
    let semestre_freq: String?
    let appelliEsame: [ExamDTO]?

    /// Falls back to the class code when the plan code is absent, since one of
    /// the two is what identifies a teaching.
    var identifier: String? {
        if let c_insegn_piano, !c_insegn_piano.isEmpty { return c_insegn_piano }
        return c_classe_m.map(String.init)
    }

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

nonisolated struct TeachingsResponse: Decodable, Sendable {
    let INSEGN: [TeachingDTO]?

    var teachings: [TeachingDTO] { INSEGN ?? [] }
}
