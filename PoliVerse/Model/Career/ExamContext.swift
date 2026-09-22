import Foundation

/// What the rest of the app knows around one sitting: the teaching's libretto row,
/// the course's other sittings, and what a mark would do to the average.
///
/// Built from data already loaded, so the exam sheet needs no request of its own.
nonisolated struct ExamContext: Sendable, Equatable {
    /// The teaching's libretto row, for its credits and whether it is already recorded.
    let librettoEntry: LibrettoExam?
    /// The course's other sittings still ahead, soonest first.
    let otherUpcoming: [ExamSession]
    /// The course's earlier marked sittings, newest first.
    let previousAttempts: [ExamSession]
    /// What this sitting's mark would do to the weighted average, or `nil` when it
    /// cannot be computed. See ``impact(of:entry:libretto:)``.
    let meanImpact: MeanImpact?

    /// The weighted average before and after a mark is recorded.
    struct MeanImpact: Sendable, Equatable {
        /// The average of the marks already recorded.
        let before: Double
        /// The average once this mark is recorded.
        let after: Double
        /// The teaching's credits, which weight the new mark.
        let cfu: Int
        /// How far the average moves.
        var delta: Double { after - before }
    }

    /// Assembles the context for one sitting.
    ///
    /// The libretto row and the course's other sittings are matched through
    /// ``ExamSession/isOf(courseCode:courseName:)``, so a blank code cannot match an
    /// unrelated row.
    ///
    /// - Parameters:
    ///   - exam: The sitting the sheet is about.
    ///   - sittings: Every sitting known.
    ///   - libretto: The student's libretto.
    ///   - now: The moment that separates past from future.
    init(exam: ExamSession, sittings: [ExamSession], libretto: [LibrettoExam], now: Date) {
        // `isOf` compares the row's id against the sitting's code itself. A
        // plain `==` would add nothing, and would match two *blank* ids,
        // handing this exam the first libretto row that happened to have none.
        let entry = libretto.first { exam.isOf(courseCode: $0.id, courseName: $0.name) }
        librettoEntry = entry

        let course = sittings.filter { $0.id != exam.id && $0.isOf(courseCode: exam.courseCode, courseName: exam.courseName) }
        otherUpcoming = course
            .filter { $0.grade == nil && ($0.date ?? .distantPast) > now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        previousAttempts = course
            .filter { $0.grade != nil && ($0.date ?? .distantPast) < (exam.date ?? now) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        meanImpact = Self.impact(of: exam.grade, entry: entry, libretto: libretto)
    }

    /// What a mark would do to the credit-weighted average.
    ///
    /// Computed only for a passed numeric mark of at least 18 that is not yet recorded:
    /// a recorded mark is already in the average, and a fail never enters it. Marks are
    /// capped at 30, so honours do not inflate the figure.
    ///
    /// - Parameters:
    ///   - grade: The published mark.
    ///   - entry: The teaching's libretto row, for its credits.
    ///   - libretto: The libretto the current average is computed from.
    /// - Returns: The impact, or `nil` when the mark is already recorded, has no number,
    ///   or the credits are unknown on either side.
    static func impact(of grade: ExamGrade?, entry: LibrettoExam?, libretto: [LibrettoExam]) -> MeanImpact? {
        guard let grade, grade.passed, let value = grade.value, value >= 18,
              let entry, !entry.isPassed, let cfu = entry.cfu, cfu > 0 else { return nil }
        let marks = libretto.compactMap { exam -> (Int, Int)? in
            guard exam.isPassed, let mark = exam.grade, mark > 0, let cfu = exam.cfu, cfu > 0 else { return nil }
            return (mark, cfu)
        }
        let credits = marks.reduce(0) { $0 + $1.1 }
        guard credits > 0 else { return nil }
        let points = marks.reduce(0) { $0 + $1.0 * $1.1 }
        return MeanImpact(
            before: Double(points) / Double(credits),
            after: Double(points + min(value, 30) * cfu) / Double(credits + cfu),
            cfu: cfu)
    }
}
