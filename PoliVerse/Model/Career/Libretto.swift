import Foundation

/// One teaching in the study plan, with its result if it has been sat.
///
/// This is the libretto — the record of what has been passed — and a different thing
/// from an ``ExamSession``, which is a sitting still open to register for. The
/// sittings endpoint is empty once everything is passed, which is exactly when a
/// student most wants to see their results.
nonisolated struct LibrettoExam: Identifiable, Sendable, Hashable, Codable {
    /// The teaching's code where the payload carries one, and the row's own id
    /// otherwise.
    let id: String
    /// The teaching's name.
    let name: String
    /// The numeric mark. Absent until the exam is sat, and absent for pass/fail
    /// teachings.
    let grade: Int?
    /// Whether the mark carries honours.
    let hasLode: Bool
    /// The teaching's credits, where recorded.
    let cfu: Int?
    /// When the exam was sat, where recorded.
    let date: Date?
    /// Upstream's own status wording, for example “Superato”.
    let statusText: String?
    /// An academic year supplied by the payload.
    ///
    /// Never filled in practice — the libretto carries no academic year, only the date
    /// of the sitting — and kept as an override for a service that does send one. Read
    /// through ``academicYear(calendar:)``.
    var year: String?

    /// Whether the teaching is passed.
    ///
    /// Taken from which list the server returned the row in rather than inferred from
    /// the mark, since a pass/fail teaching is passed with no numeric mark at all.
    let isPassed: Bool
    /// The teaching's English name, from `descrizione_eng`.
    ///
    /// With no teaching code in the libretto, the names are all there is to recognise a
    /// teaching by in the manifesto.
    var englishName: String? = nil

    /// The mark as it is shown: `"30L"` for honours, the number otherwise, and `"—"`
    /// when there is none.
    var displayGrade: String {
        guard let grade, grade > 0 else { return "—" }
        return hasLode ? "\(grade)L" : String(grade)
    }

    /// The academic year this exam was sat in, as `"2024/25"`.
    ///
    /// ``year`` wins when it is filled; otherwise it is derived from ``date``, with the
    /// boundary on 1 October so that the autumn session counts under the year whose
    /// teaching it examines.
    ///
    /// - Parameter calendar: The calendar to read the date in.
    /// - Returns: The year label, or `nil` without a year or a date.
    func academicYear(calendar: Calendar = PoliMiDate.romeCalendar) -> String? {
        if let year, !year.isEmpty { return year }
        guard let date else { return nil }
        return PoliMiDate.academicYear(ofSitting: date, calendar: calendar)
    }
}
