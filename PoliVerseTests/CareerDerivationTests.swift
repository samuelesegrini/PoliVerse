import Foundation
import Testing
@testable import PoliVerse

/// The arithmetic that used to live on ``CareerModel``, where reaching it meant
/// standing up a ``Session``.
///
/// Two of these figures existed twice before the move: `CareerModel` had its
/// own weighted mean *and* used ``StudyPlan``'s through `meanDelta`, so a
/// change to one would have silently disagreed with the other. There is one
/// now, and these pin it.
@Suite("Career arithmetic")
struct CareerDerivationTests {
    private static func exam(_ id: String, grade: Int?, cfu: Int?, day: Int?,
                             passed: Bool = true) -> LibrettoExam {
        LibrettoExam(
            id: id, name: id, grade: grade, hasLode: false, cfu: cfu,
            date: day.map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 86_400) },
            statusText: nil, isPassed: passed)
    }

    // MARK: - The mean

    @Test("Marks are weighted by credits")
    func weightedByCFU() throws {
        let plan = StudyPlan(exams: [
            Self.exam("a", grade: 30, cfu: 10, day: 1),
            Self.exam("b", grade: 20, cfu: 5, day: 2),
        ])
        // (30×10 + 20×5) / 15
        #expect(try #require(plan.weightedMean) == 400.0 / 15.0)
    }

    /// Pass/fail teachings carry credits but no mark. Counting them as zero
    /// would wreck every average they appear in.
    @Test("A pass/fail teaching does not drag the average down")
    func idoneitaIsNotAZero() throws {
        let plan = StudyPlan(exams: [
            Self.exam("a", grade: 30, cfu: 10, day: 1),
            Self.exam("idoneita", grade: nil, cfu: 5, day: 2),
        ])
        #expect(try #require(plan.weightedMean) == 30)
    }

    /// Some rows arrive with no credits at all; dividing by zero would report
    /// nothing rather than the obvious answer.
    @Test("With no credits recorded anywhere, a plain mean is used")
    func fallsBackToAPlainMean() throws {
        let plan = StudyPlan(exams: [
            Self.exam("a", grade: 30, cfu: nil, day: 1),
            Self.exam("b", grade: 20, cfu: nil, day: 2),
        ])
        #expect(try #require(plan.weightedMean) == 25)
    }

    @Test("An empty plan has no mean rather than a zero")
    func emptyPlanHasNoMean() {
        #expect(StudyPlan(exams: []).weightedMean == nil)
        #expect(StudyPlan(exams: []).lastGraded == nil)
        #expect(StudyPlan(exams: []).meanDelta == nil)
    }

    // MARK: - Which way it is going

    @Test("The most recent dated mark is the last graded")
    func lastGradedIsTheMostRecent() throws {
        let plan = StudyPlan(exams: [
            Self.exam("older", grade: 25, cfu: 5, day: 1),
            Self.exam("newer", grade: 30, cfu: 5, day: 9),
        ])
        #expect(try #require(plan.lastGraded).id == "newer")
    }

    /// "Most recent" is a question about time, and an undated exam cannot
    /// answer it.
    @Test("An undated mark is never the last graded")
    func undatedIsNeverLast() throws {
        let plan = StudyPlan(exams: [
            Self.exam("dated", grade: 25, cfu: 5, day: 1),
            Self.exam("undated", grade: 30, cfu: 5, day: nil),
        ])
        #expect(try #require(plan.lastGraded).id == "dated")
    }

    @Test("A mark above the average moves it up, and by how much")
    func deltaIsSigned() throws {
        let plan = StudyPlan(exams: [
            Self.exam("first", grade: 20, cfu: 5, day: 1),
            Self.exam("second", grade: 30, cfu: 5, day: 2),
        ])
        // 20 alone, then 25 with both: up five.
        #expect(try #require(plan.meanDelta) == 5)

        let down = StudyPlan(exams: [
            Self.exam("first", grade: 30, cfu: 5, day: 1),
            Self.exam("second", grade: 20, cfu: 5, day: 2),
        ])
        #expect(try #require(down.meanDelta) == -5)
    }

    /// Nil until there are two marks to have moved between — a first exam has
    /// not moved anything.
    @Test("One mark has no delta")
    func singleMarkHasNoDelta() {
        #expect(StudyPlan(exams: [Self.exam("only", grade: 28, cfu: 5, day: 1)]).meanDelta == nil)
    }

    // MARK: - Sittings

    private static func sitting(_ id: Int, day: Double?, status: ExamStatus = .open) -> ExamSession {
        ExamSession(
            id: id, courseName: "Corso \(id)", courseCode: "C\(id)", teacher: nil,
            date: day.map { Date(timeIntervalSince1970: 1_700_000_000 + $0 * 86_400) },
            room: nil, enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
            kind: nil, status: status)
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000 + 5 * 86_400)

    @Test("Upcoming sittings are those ahead, soonest first")
    func upcomingIsSorted() {
        let sittings = Sittings([
            Self.sitting(1, day: 9), Self.sitting(2, day: 1), Self.sitting(3, day: 7),
        ])
        #expect(sittings.upcoming(now: Self.now).map(\.id) == [3, 1])
    }

    /// A sitting this morning is still today's exam at two in the afternoon;
    /// dropping it the moment it started takes it off the screen of the
    /// student walking into it.
    @Test("A sitting earlier today is still upcoming")
    func todayCountsAllDay() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Self.now)
        let thisMorning = ExamSession(
            id: 1, courseName: "Analisi", courseCode: "A", teacher: nil,
            date: today, room: nil, enrolmentOpens: nil, enrolmentCloses: nil,
            enrolledCount: nil, kind: nil, status: .enrolled)

        let sittings = Sittings([thisMorning])
        let later = today.addingTimeInterval(14 * 3600)

        #expect(sittings.upcoming(now: later, calendar: calendar).count == 1)
        // But the widget's "next exam" must not claim one that has started.
        #expect(sittings.next(after: later) == nil)
    }

    @Test("A graded sitting is behind the student, whatever its date")
    func gradedIsNotUpcoming() {
        let graded = Self.sitting(1, day: 9, status: .graded(
            ExamGrade(value: 28, text: "28", passed: true, refusable: false)))
        #expect(Sittings([graded]).upcoming(now: Self.now).isEmpty)
    }

    @Test("Enrolled is the subset of upcoming the student signed up for")
    func enrolledIsASubset() {
        let sittings = Sittings([
            Self.sitting(1, day: 7, status: .enrolled),
            Self.sitting(2, day: 8, status: .open),
        ])
        #expect(sittings.enrolled(now: Self.now).map(\.id) == [1])
    }
}
