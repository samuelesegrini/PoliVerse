import Foundation

/// How a teaching the student is taking is looked up in the manifesto.
///
/// The lookup needs all four members, because none of them is reliable alone. The
/// teaching code is missing from WeBeep pages titled with a name only, and where it
/// exists it is not unique — one account can hold several courses sharing a code. The
/// name is normalised and so comparable, but two degree courses can teach something of
/// the same name. The year narrows the manifesto to one edition, and the course id is
/// what ties a result back to the row on screen.
nonisolated struct TeachingRef: Sendable, Hashable {
    /// The Politecnico teaching code, where the source carries one.
    let code: String?
    /// The teaching's name, normalised the way ``Course/normalise(_:)`` normalises it, which
    /// is what makes a name-based match possible.
    let name: String
    /// The academic year, as the manifesto keys it — `"2025"` for 2025/26.
    let yearCode: String?
    /// The course row this lookup is on behalf of, where there is one.
    let courseID: String?

    /// Creates a reference.
    ///
    /// - Parameters:
    ///   - code: The teaching code, where there is one.
    ///   - name: The teaching's normalised name.
    ///   - yearCode: The academic year the manifesto should be read for.
    ///   - courseID: The course row this is on behalf of.
    init(code: String?, name: String, yearCode: String?, courseID: String? = nil) {
        self.code = code
        self.name = name
        self.yearCode = yearCode
        self.courseID = courseID
    }

    /// A reference for a teaching the student is enrolled in.
    ///
    /// - Parameter course: The enrolled course.
    init(_ course: Course) {
        self.init(code: course.teachingCode, name: course.name,
                  yearCode: course.academicYearStart, courseID: course.id)
    }

    /// A reference for the teaching an exam sitting is of.
    ///
    /// The year comes from the date of the sitting through
    /// ``PoliMiDate/academicYear(ofSitting:calendar:)``, whose boundary is October, rather
    /// than through ``Course/academicYearLabel(for:)``, whose boundary is September. A
    /// September sitting read the second way would be looked up in the following year's
    /// manifesto — a different edition, with different lecturers and a different scheda.
    ///
    /// - Parameter sitting: The exam sitting.
    init(_ sitting: ExamSession) {
        self.init(code: sitting.courseCode,
                  name: sitting.courseName,
                  yearCode: sitting.date
                      .flatMap { PoliMiDate.academicYear(ofSitting: $0) }
                      .map { String($0.prefix(4)) })
    }

    /// The codes to search by. Empty when the source carried none, which is the WeBeep-page
    /// case and falls back to the name.
    var codes: [String] { [code].compactMap { $0 } }
}
