import Foundation
import Testing
@testable import PoliVerse

/// How a teaching is found in the manifesto.
///
/// These rules were spread across four method signatures and the views that
/// called them; the year rule in particular lived inline in
/// `ExamFormatSection`, where nothing could reach it. Naming the concept is
/// what made them testable — the type needs no session, no network and no
/// model to answer.
@Suite("Teaching reference")
struct TeachingRefTests {
    private static func course(code: String?, name: String, year: String) -> Course {
        Course(id: "wb-1", name: name, teacher: "—", cfu: 0, semester: "1",
               academicYear: year, code: code)
    }

    private static func sitting(on date: Date?) -> ExamSession {
        ExamSession(id: 1, courseName: "Analisi", courseCode: "086457", teacher: nil,
                    date: date, room: nil, enrolmentOpens: nil, enrolmentCloses: nil,
                    enrolledCount: nil, kind: nil, status: .open)
    }

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        PoliMiDate.romeCalendar.date(
            from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
    }

    // MARK: - From a course

    @Test("A course carries its code, name and the year its edition started")
    func fromCourse() {
        let ref = TeachingRef(Self.course(code: "086457", name: "Analisi", year: "2025/26"))

        #expect(ref.code == "086457")
        #expect(ref.name == "Analisi")
        #expect(ref.yearCode == "2025")
        #expect(ref.courseID == "wb-1")
        #expect(ref.codes == ["086457"])
    }

    /// A WeBeep page titled with a name only has no teaching code, which is the
    /// whole reason the name and year are part of the lookup at all.
    @Test("A course with no code searches by name, not by an empty code")
    func courseWithoutACode() {
        let ref = TeachingRef(Self.course(code: nil, name: "Analisi", year: "2025/26"))

        #expect(ref.code == nil)
        // Empty rather than [nil] or [""]: a blank code must never be matched
        // against another blank code, which would make every uncoded teaching
        // the same teaching.
        #expect(ref.codes.isEmpty)
        #expect(ref.name == "Analisi")
    }

    // MARK: - From a sitting, which is where the rule lives

    /// An exam sat in the winter session belongs to the year that is *ending*.
    /// A January sitting is 2025/26, and taking the year from the clock would
    /// file it under 2026/27 — a different edition of the manifesto, with
    /// different lecturers and a different scheda.
    @Test("A January sitting belongs to the academic year that is ending")
    func winterSessionBelongsToTheEndingYear() {
        let ref = TeachingRef(Self.sitting(on: Self.day(2026, 1, 20)))
        #expect(ref.yearCode == "2025")
    }

    /// The case that was wrong before this rule was named. The autumn session
    /// examines the year that is closing, so a September sitting is the
    /// *previous* edition's — the exam-scheda screen used the course rule
    /// (September opens the year) and looked it up a year out.
    @Test("A September sitting belongs to the year that is ending, not opening")
    func autumnSessionBelongsToTheEndingYear() {
        let ref = TeachingRef(Self.sitting(on: Self.day(2026, 9, 5)))
        #expect(ref.yearCode == "2025")
        // And the course rule deliberately disagrees, because a teaching does
        // start in September. The two must not be swapped for one another.
        #expect(Course.academicYearLabel(for: Self.day(2026, 9, 5)).hasPrefix("2026"))
    }

    /// October is where the sitting year turns over.
    @Test("An October sitting belongs to the year that is opening")
    func octoberOpensTheNewYear() {
        let ref = TeachingRef(Self.sitting(on: Self.day(2026, 10, 1)))
        #expect(ref.yearCode == "2026")
    }

    /// The libretto had this rule written out correctly all along; it now uses
    /// the same named one, so the two cannot drift apart again.
    @Test("The libretto and the scheda agree on a sitting's year")
    func librettoAgrees() {
        let date = Self.day(2026, 9, 5)
        let exam = LibrettoExam(id: "x", name: "Analisi", grade: 28, hasLode: false,
                                cfu: 5, date: date, statusText: nil, isPassed: true)
        #expect(exam.academicYear() == "2025/26")
        #expect(TeachingRef(Self.sitting(on: date)).yearCode == "2025")
    }

    /// A sitting with no date cannot be placed in a year, and guessing one
    /// would point the lookup at an edition chosen by the clock.
    @Test("An undated sitting claims no year rather than guessing one")
    func undatedSittingHasNoYear() {
        let ref = TeachingRef(Self.sitting(on: nil))

        #expect(ref.yearCode == nil)
        #expect(ref.code == "086457")
        // No course row to tie a result back to.
        #expect(ref.courseID == nil)
    }
}
