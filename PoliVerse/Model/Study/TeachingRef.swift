import Foundation

/// How a teaching the student is taking is looked up in the manifesto.
///
/// ## The concept this names
///
/// Four methods on ``StudyProgrammeModel`` took the same four parameters —
/// `teachingCode`, `name`, `yearCode`, `courseID` — and every call site built
/// them inline from a ``Course`` or an ``ExamSession``. The tuple was the
/// concept; it just had no name, so each caller re-derived it and the rules for
/// deriving it lived in whichever view happened to need them.
///
/// The lookup needs all four because none of them is reliable alone. The
/// teaching code is missing from WeBeep pages titled with a name only, and it
/// is **not unique** where it exists — a real account has several courses
/// sharing one, the same teaching across years or a lecture and its lab. The
/// name is normalised and so comparable, but two degree courses can teach
/// something of the same name. The year narrows the manifesto to one edition,
/// and the course id is what ties a result back to the row on screen.
nonisolated struct TeachingRef: Sendable, Hashable {
    /// The Politecnico teaching code, where the source carries one.
    let code: String?
    /// The teaching's name, normalised the way ``Course`` normalises it, so
    /// that a name-based match is possible at all.
    let name: String
    /// The academic year the teaching belongs to, as the manifesto spells it.
    let yearCode: String?
    /// The course row this lookup is on behalf of, where there is one.
    let courseID: String?

    init(code: String?, name: String, yearCode: String?, courseID: String? = nil) {
        self.code = code
        self.name = name
        self.yearCode = yearCode
        self.courseID = courseID
    }

    /// A teaching the student is enrolled in.
    init(_ course: Course) {
        self.init(code: course.teachingCode, name: course.name,
                  yearCode: course.academicYearStart, courseID: course.id)
    }

    /// The teaching an exam sitting is of.
    ///
    /// The year comes from the date of the sitting, through
    /// ``PoliMiDate/academicYear(ofSitting:calendar:)`` — *not* through
    /// ``Course/academicYearLabel(for:)``, which draws the boundary a month
    /// earlier because it answers a different question.
    ///
    /// The view this rule was lifted from used the course one, so a sitting in
    /// the September session was looked up in the following year's manifesto:
    /// a different edition, with different lecturers and a different scheda.
    /// It is arithmetic over a date, so it now lives somewhere it can be
    /// tested — which is how that was noticed.
    init(_ sitting: ExamSession) {
        self.init(code: sitting.courseCode,
                  name: sitting.courseName,
                  yearCode: sitting.date
                      .flatMap { PoliMiDate.academicYear(ofSitting: $0) }
                      .map { String($0.prefix(4)) })
    }

    /// The codes to search by: none where the source carried no code, which is
    /// the WeBeep-page case and has to fall back to the name.
    var codes: [String] { [code].compactMap { $0 } }
}
