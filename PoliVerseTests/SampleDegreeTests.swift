import Foundation
import Testing
@testable import PoliVerse

/// The demo is one career, not one per screen.
///
/// These are the invariants that broke last time: a libretto adding up to one
/// average while the gradebook carried another, a course worth 10 CFU on its
/// own page and 8 in the plan, sittings for teachings that were not in the
/// plan at all. Each is cheap to re-break by hand-editing one sample, so each
/// is pinned here.
@Suite("Sample degree")
struct SampleDegreeTests {
    private let teachings = SampleDegree.teachings
    private let libretto = LibrettoExam.samples()

    @Test("A whole triennale: 180 CFU over three years, every code its own")
    func plan() {
        #expect(SampleDegree.plannedCFU == 180)
        #expect(Set(teachings.map(\.code)).count == teachings.count)
        #expect(Set(teachings.map(\.year)) == [1, 2, 3])
        #expect(teachings.allSatisfy { $0.semester == 1 || $0.semester == 2 })
    }

    @Test("The gradebook is a reading of the libretto, not a second opinion")
    func gradeBookAgreesWithLibretto() {
        let plan = StudyPlan(exams: libretto)
        let book = GradeBook.sample
        #expect(book.mean == plan.weightedMean)
        #expect(book.earnedCFU == plan.earnedCFU)
        #expect(book.plannedCFU == plan.totalCFU)
        #expect(book.examsPlanned == teachings.count)
        #expect(book.examsGiven == teachings.filter(\.isPassed).count)
    }

    @Test("A course's credits are the plan's credits")
    func coursesAgreeWithPlan() throws {
        for course in Course.samples {
            let teaching = try #require(teachings.first { $0.code == course.id },
                                        "\(course.name) is not in the plan")
            #expect(course.cfu == teaching.cfu)
            #expect(course.name == teaching.name)
            #expect(course.teacher == teaching.teacher)
        }
    }

    @Test("Every sitting and every update belongs to a teaching in the plan")
    func sittingsBelongToThePlan() {
        let codes = Set(teachings.map(\.code))
        #expect(ExamSession.samples().allSatisfy { codes.contains($0.courseCode) })
        #expect(ExamUpdate.samples().allSatisfy { codes.contains($0.courseCode) })
        #expect(libretto.allSatisfy { codes.contains($0.id) })
    }

    @Test("An idoneità carries credits but no mark, and moves no average")
    func qualifyingStaysOutOfTheMean() throws {
        let english = try #require(libretto.first { $0.id == "088786" })
        #expect(english.grade == nil)
        #expect(english.isPassed)
        #expect((english.cfu ?? 0) > 0)

        // Removing it must not shift the average by a hair.
        let without = libretto.filter { $0.id != english.id }
        #expect(StudyPlan(exams: libretto).weightedMean == StudyPlan(exams: without).weightedMean)
        #expect(StudyPlan(exams: libretto).earnedCFU > StudyPlan(exams: without).earnedCFU)
    }

    @Test("A teaching failed once and passed later keeps both sittings, and counts once")
    func retakes() throws {
        let probability = try #require(teachings.first { $0.code == "097671" })
        #expect(probability.attempts.count == 2)
        #expect(probability.isPassed)
        #expect(probability.mark == 22)

        let sittings = ExamSession.samples().filter { $0.courseCode == probability.code }
        #expect(sittings.count == 2)
        #expect(sittings.filter { $0.grade?.passed == true }.count == 1)
        // Counted once in the libretto, at the mark that stands.
        let rows = libretto.filter { $0.id == probability.code }
        #expect(rows.count == 1)
        #expect(rows.first?.grade == 22)
    }

    @Test("The demo shows every state a sitting can be in")
    func everyStatusIsRepresented() {
        let sessions = ExamSession.samples()
        #expect(sessions.contains { $0.status == .enrolled })
        #expect(sessions.contains { $0.status == .open })
        #expect(sessions.contains { $0.status == .closed })
        #expect(sessions.contains { $0.status == .notYetOpen })
        #expect(sessions.contains { $0.grade?.passed == true })
        #expect(sessions.contains { $0.grade?.passed == false })
        #expect(sessions.contains { $0.grade?.refusable == true })
        #expect(sessions.contains { $0.grade?.value == 30 && $0.grade?.text.contains("lode") == true })
    }

    @Test("Adesso has all three of its cards to draw")
    func deadlinesCoverEveryKind() {
        let kinds = CareerDeadline.all(in: ExamSession.samples()).map(\.kind)
        #expect(kinds.contains { if case .sitting = $0 { true } else { false } })
        #expect(kinds.contains { if case .enrolmentClosing = $0 { true } else { false } })
        #expect(kinds.contains { if case .refusableGrade = $0 { true } else { false } })
    }

    @Test("Several ways of being examined, so the format section has something to say")
    func assessmentsVary() {
        let kinds = Set(teachings.map(\.assessment))
        #expect(kinds.count >= 5)
        #expect(kinds.contains(.project))
        #expect(kinds.contains(.qualifying))
    }

    @Test("The week's lessons are teachings the student is actually taking")
    func timetableFollowsThePlan() {
        let current = Set(SampleDegree.currentTeachings.map(\.name))
        let lessons = AgendaEvent.samples(around: .now).filter { $0.kind == .lecture }
        #expect(!lessons.isEmpty)
        // Two things the comparison has to tolerate. Titles may carry a suffix
        // ("— laboratorio"), so it is a prefix match; and they arrive SHOUTED,
        // because the sample timetable mimics what the service actually sends
        // — which is the whole reason ``Course/normalise(_:)`` exists.
        #expect(lessons.allSatisfy { lesson in
            current.contains { lesson.title.lowercased().hasPrefix($0.lowercased()) }
        })
    }

    @Test("Nothing already passed is still offered as something to sit")
    func passedTeachingsHaveNoOpenSittings() {
        let passed = Set(teachings.filter(\.isPassed).map(\.code))
        let open = ExamSession.samples().filter { $0.grade == nil }
        #expect(open.allSatisfy { !passed.contains($0.courseCode) })
    }

    @Test("Oggi's Scadenze card has something to show")
    func deadlinesExist() {
        let deadlines = AssignmentDeadline.samples()
        #expect(deadlines.count >= 3)
        // Ahead of now, soonest first, and each belonging to a real teaching.
        #expect(deadlines.allSatisfy { $0.due > .now })
        #expect(deadlines == deadlines.sorted { $0.due < $1.due })
        let codes = Set(SampleDegree.teachings.map(\.code))
        #expect(deadlines.allSatisfy { codes.contains($0.courseCode) })
    }

    @Test("A hand-in already closed is not offered as a deadline")
    func closedAssignmentsAreDropped() {
        let planned = SampleDegree.teachings.flatMap(\.assignments)
        #expect(planned.contains { $0.dueInDays < 0 }, "the plan should carry a closed one to exclude")
        #expect(AssignmentDeadline.samples().count < planned.count)
    }

    @Test("Two courses do not show the same material")
    func materialsDifferPerCourse() throws {
        let courses = Course.samples
        let named = courses.map { course in
            Set(WeBeepSection.samples(for: course).flatMap(\.files).map(\.name))
        }
        // Every course has files, and no two carry an identical set.
        #expect(named.allSatisfy { !$0.isEmpty })
        for (a, b) in zip(named, named.dropFirst()) {
            #expect(a != b)
        }
        // Lecture files follow the teaching's own topics.
        let databases = try #require(courses.first { $0.id == "095946" })
        let files = WeBeepSection.samples(for: databases).flatMap(\.files).map(\.name)
        #expect(files.contains { $0.contains("Algebra relazionale") })
    }

    @Test("Marks were earned in a plausible order, oldest first year to newest")
    func datesRunForward() throws {
        for teaching in teachings where teaching.attempts.count > 1 {
            let months = teaching.attempts.map(\.monthsAgo)
            #expect(months == months.sorted(by: >), "\(teaching.name) sits out of order")
        }
        let firstYear = try #require(teachings.first { $0.year == 1 && !$0.attempts.isEmpty })
        let thirdYearish = try #require(teachings.first { $0.code == "095946" })
        #expect((firstYear.attempts.first?.monthsAgo ?? 0) > (thirdYearish.attempts.last?.monthsAgo ?? 0))
    }
}
