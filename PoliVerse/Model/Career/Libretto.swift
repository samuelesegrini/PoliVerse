import Foundation

/// One teaching in the study plan, with its result if it has been sat.
///
/// This is the libretto — the record of what has actually been passed. It is a
/// different thing from an exam *sitting*: `/v1/insegn` lists sittings still
/// open to register for and is empty once everything is passed, which is
/// exactly when a student most wants to see their results.
nonisolated struct LibrettoExam: Identifiable, Sendable, Hashable, Codable {
    let id: String
    let name: String
    /// Absent until the exam is sat; also absent for pass/fail teachings.
    let grade: Int?
    let hasLode: Bool
    let cfu: Int?
    let date: Date?
    /// Upstream's own status wording, e.g. "Superato".
    let statusText: String?
    /// Academic year the teaching belongs to, for grouping a study plan.
    var year: String?

    /// Taken from which list the server returned this row in, rather than
    /// inferred from the mark — a pass/fail teaching ("idoneità") is passed
    /// with no numeric mark at all.
    let isPassed: Bool
    /// `descrizione_eng`. With no teaching code in the libretto, the names are
    /// all there is to recognise a teaching by in the manifesto.
    var englishName: String? = nil

    /// `30L` for a mark with honours, matching how the official app renders it.
    var displayGrade: String {
        guard let grade, grade > 0 else { return "—" }
        return hasLode ? "\(grade)L" : String(grade)
    }
}
