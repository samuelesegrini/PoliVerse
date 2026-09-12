import Foundation
import Testing
@testable import PoliVerse

/// "What do I need in the next four exams to reach 27?"
///
/// The arithmetic is done here rather than taken from the server. The
/// Politecnico has `/simulazionemedia` and `/mediaobiettivo`, and the app uses
/// them for the official target — but the answer to a hypothetical must be
/// instant and offline, and it is a weighted mean over data already on the
/// device. A round trip per slider drag would be absurd.
@Suite("Grade simulation")
struct GradeSimulationTests {
    private func exam(_ grade: Int?, _ cfu: Int, lode: Bool = false) -> LibrettoExam {
        LibrettoExam(id: UUID().uuidString, name: "Esame", grade: grade,
                     hasLode: lode, cfu: cfu, date: nil, statusText: nil,
                     isPassed: grade != nil)
    }

    @Test("The weighted mean follows CFU, not exam count")
    func weightedMean() {
        // 30×10 + 20×5 = 400 over 15 CFU = 26.67, not the unweighted 25.
        let plan = StudyPlan(exams: [exam(30, 10), exam(20, 5)])
        #expect(abs((plan.weightedMean ?? 0) - 26.666) < 0.01)
    }

    /// `30L` counts as 30 in the weighted mean. The Politecnico awards honours
    /// on top of a 30; treating it as 31 or 33 inflates every average that
    /// contains one.
    @Test("Honours count as thirty, not more")
    func lodeIsThirty() {
        let plan = StudyPlan(exams: [exam(30, 10, lode: true)])
        #expect(plan.weightedMean == 30)
    }

    /// Pass/fail teachings carry CFU but no mark, and including them at zero
    /// would destroy the average.
    @Test("Ungraded passes are excluded from the mean")
    func idoneitaExcluded() {
        let plan = StudyPlan(exams: [exam(28, 6), exam(nil, 6)])
        #expect(plan.weightedMean == 28)
    }

    @Test("Earned CFU counts only what has been passed")
    func earnedCFU() {
        let plan = StudyPlan(exams: [exam(28, 6), exam(nil, 9)])
        #expect(plan.earnedCFU == 6)
        #expect(plan.remainingCFU == 9)
    }

    /// The headline question.
    @Test("The required average to reach a target is computed over remaining CFU")
    func requiredAverage() {
        // 27 over 10 CFU done; 20 CFU left; target 28.
        // (28×30 − 27×10) / 20 = 28.5
        let plan = StudyPlan(exams: [exam(27, 10), exam(nil, 20)])
        #expect(abs((plan.requiredAverage(for: 28) ?? 0) - 28.5) < 0.001)
    }

    @Test("A target already exceeded needs nothing more")
    func targetAlreadyMet() {
        let plan = StudyPlan(exams: [exam(30, 10), exam(nil, 10)])
        let needed = plan.requiredAverage(for: 25)
        #expect(needed != nil)
        #expect(needed! < 25)
    }

    /// The honest answer when a target is arithmetically out of reach: the
    /// number needed is above 30, and the caller must be able to see that
    /// rather than be handed a clamped 30 that looks achievable.
    @Test("An unreachable target reports a figure above thirty")
    func unreachableTarget() {
        let plan = StudyPlan(exams: [exam(18, 30), exam(nil, 10)])
        let needed = plan.requiredAverage(for: 29)
        #expect(needed != nil)
        #expect(needed! > 30)
        #expect(!plan.isReachable(29))
        // 18 over 30 CFU with 10 left caps the final mean at 21, so 22 is out
        // of reach too — the ceiling is lower than it looks, which is exactly
        // why this is worth showing honestly rather than clamping to 30.
        #expect(!plan.isReachable(22))
        #expect(plan.isReachable(20))
    }

    @Test("With nothing left to sit there is no average to require")
    func nothingRemaining() {
        let plan = StudyPlan(exams: [exam(28, 10)])
        #expect(plan.requiredAverage(for: 30) == nil)
    }

    /// Projecting the other way: what the average becomes if the rest go a
    /// given way.
    @Test("A projected mean blends what is done with what is assumed")
    func projection() {
        // 30×10 done, 10 CFU left at 24 → (300 + 240) / 20 = 27
        let plan = StudyPlan(exams: [exam(30, 10), exam(nil, 10)])
        #expect(abs((plan.projectedMean(assuming: 24) ?? 0) - 27) < 0.001)
    }

    /// The degree mark, which is what the average is actually for. The
    /// Politecnico's conversion is mean/30×110, and the app shows it as an
    /// estimate rather than a promise — thesis and honours points sit on top
    /// and are not derivable from the libretto.
    @Test("The base degree mark is the mean scaled to 110")
    func degreeMark() {
        let plan = StudyPlan(exams: [exam(27, 10)])
        #expect(plan.baseDegreeMark == 99)
    }

    @Test("An empty plan reports nothing rather than zero")
    func emptyPlan() {
        let plan = StudyPlan(exams: [])
        #expect(plan.weightedMean == nil)
        #expect(plan.baseDegreeMark == nil)
        #expect(plan.projectedMean(assuming: 30) == nil)
    }
}

/// The teacher roster, assembled from courses and sittings because there is no
/// staff directory to search.
@Suite("Teachers")
struct TeacherTests {
    private func course(_ name: String, teacher: String, email: String? = nil) -> Course {
        Course(id: name, name: name, teacher: teacher, cfu: 5,
               semester: "1", academicYear: "2025/26", teacherEmail: email)
    }

    @Test("Courses by the same person collapse into one entry")
    func grouping() {
        let roster = Teacher.roster(
            courses: [course("Analisi", teacher: "Maria Rossi"),
                      course("Geometria", teacher: "Maria Rossi")],
            sessions: [])
        #expect(roster.count == 1)
        #expect(roster[0].courses.count == 2)
    }

    /// `/v1/insegn` shouts names while other endpoints title-case them, so the
    /// same person would otherwise appear twice.
    @Test("Shouted and title-cased names are the same person")
    func casing() {
        let roster = Teacher.roster(
            courses: [course("Analisi", teacher: "MARIA ROSSI"),
                      course("Geometria", teacher: "Maria Rossi")],
            sessions: [])
        #expect(roster.count == 1)
        #expect(roster[0].name == "Maria Rossi")
    }

    /// "—" is how these endpoints spell "no teacher recorded"; without this it
    /// becomes a person by that name, at the top of every search.
    @Test("Placeholders do not become people")
    func placeholders() {
        let roster = Teacher.roster(
            courses: [course("Analisi", teacher: "—"), course("Fisica", teacher: "-")],
            sessions: [])
        #expect(roster.isEmpty)
    }

    @Test("An email is kept from whichever source has one")
    func email() {
        let roster = Teacher.roster(
            courses: [course("Analisi", teacher: "Maria Rossi"),
                      course("Geometria", teacher: "Maria Rossi", email: "maria@polimi.it")],
            sessions: [])
        #expect(roster[0].email == "maria@polimi.it")
    }

    @Test("Search matches on name and on email")
    func matching() {
        let teacher = Teacher(name: "Maria Rossi", email: "maria.rossi@polimi.it", courses: [])
        #expect(teacher.matches("rossi"))
        #expect(teacher.matches("ROSSI"))
        #expect(teacher.matches("maria.rossi@"))
        #expect(!teacher.matches("bianchi"))
    }
}

/// The plan header is decoration around the exam list; a missing field must
/// not cost the screen, but nothing readable at all is not a header.
@Suite("Study plan header")
struct StudyPlanHeaderTests {
    private func header(_ json: String) -> StudyPlanHeader? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        else { return nil }
        return StudyPlanHeader(value: value)
    }

    @Test("A plausible header decodes")
    func decodes() {
        let parsed = header("""
        {"descrizione_corso":"Ingegneria Informatica","aa":"2025/26",
         "orientamento":"Software","cfu_totali":120}
        """)
        #expect(parsed?.course == "Ingegneria Informatica")
        #expect(parsed?.totalCFU == 120)
    }

    @Test("A header wrapped in an array is still found")
    func wrapped() {
        #expect(header("""
        [{"corso":"Matematica"}]
        """)?.course == "Matematica")
    }

    @Test("Nothing readable is no header at all")
    func empty() {
        #expect(header("""
        {"qualcosa":"altro"}
        """) == nil)
    }
}
