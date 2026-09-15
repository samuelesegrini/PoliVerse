import Foundation

/// What the profile shows about a student's career, worked out once from the
/// libretto, the grade book and the plan header the app already loads.
nonisolated struct ProfileSummary: Equatable, Sendable {
    struct Mark: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let grade: Int
        let honours: Bool
        let cfu: Int
        let date: Date
    }

    /// A milestone earned on the way to the degree.
    enum Badge: String, CaseIterable, Identifiable, Sendable {
        case firstExam, fiveExams, tenExams, firstThirty, honours, fiftyCredits, halfway, highAverage, allPassedThisYear
        var id: String { rawValue }
    }

    /// CFU-weighted mean of the numeric marks; the official mean when there
    /// are none to weigh.
    let mean: Double?
    /// The degree mark the mean is worth before any bonus: `mean × 110 / 30`.
    var graduationBase: Double? { mean.map { $0 * 110 / 30 } }
    let earnedCFU: Int
    let plannedCFU: Int
    var progress: Double { plannedCFU > 0 ? min(Double(earnedCFU) / Double(plannedCFU), 1) : 0 }
    let passedCount: Int
    let pendingCount: Int
    let honoursCount: Int
    let best: Mark?
    /// Passed exams with a mark, oldest first, for the trend.
    let marks: [Mark]
    let course: String?
    let year: String?
    let badges: [Badge]

    init(libretto: [LibrettoExam], gradeBook: GradeBook, header: StudyPlanHeader?) {
        let passed = libretto.filter(\.isPassed)
        marks = passed.compactMap { exam in
            guard let grade = exam.grade, grade > 0, let date = exam.date else { return nil }
            return Mark(id: exam.id, name: exam.name, grade: grade, honours: exam.hasLode, cfu: exam.cfu ?? 0, date: date)
        }
        .sorted { $0.date < $1.date }

        let weighted = marks.filter { $0.cfu > 0 }
        let weight = weighted.reduce(0) { $0 + $1.cfu }
        if weight > 0 {
            mean = Double(weighted.reduce(0) { $0 + $1.grade * $1.cfu }) / Double(weight)
        } else {
            mean = gradeBook.mean > 0 ? gradeBook.mean : nil
        }

        let librettoCFU = passed.reduce(0) { $0 + ($1.cfu ?? 0) }
        earnedCFU = max(gradeBook.earnedCFU, librettoCFU)
        plannedCFU = max(gradeBook.plannedCFU, header?.totalCFU ?? 0, libretto.reduce(0) { $0 + ($1.cfu ?? 0) })
        passedCount = passed.count
        pendingCount = libretto.count - passed.count
        honoursCount = marks.filter(\.honours).count
        best = marks.max { ($0.grade, $0.honours ? 1 : 0) < ($1.grade, $1.honours ? 1 : 0) }
        course = header?.course
        year = header?.year

        var badges: [Badge] = []
        if passedCount >= 1 { badges.append(.firstExam) }
        if passedCount >= 5 { badges.append(.fiveExams) }
        if passedCount >= 10 { badges.append(.tenExams) }
        if marks.contains(where: { $0.grade >= 30 }) { badges.append(.firstThirty) }
        if honoursCount > 0 { badges.append(.honours) }
        if earnedCFU >= 50 { badges.append(.fiftyCredits) }
        if plannedCFU > 0, earnedCFU * 2 >= plannedCFU { badges.append(.halfway) }
        if let mean, mean >= 27 { badges.append(.highAverage) }
        self.badges = badges
    }
}
