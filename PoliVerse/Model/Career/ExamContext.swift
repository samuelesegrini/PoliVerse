import Foundation

/// What the rest of the app knows around one sitting: the teaching's libretto
/// row, the course's other sittings, and what a mark would do to the mean.
///
/// Built from data already loaded, so the exam sheet can show it without a
/// request of its own.
nonisolated struct ExamContext: Sendable, Equatable {
    /// The teaching in the libretto, for its CFU and whether it is recorded.
    let librettoEntry: LibrettoExam?
    /// The course's other sittings still ahead, soonest first.
    let otherUpcoming: [ExamSession]
    /// The course's earlier sittings that have a mark, newest first.
    let previousAttempts: [ExamSession]
    /// The CFU-weighted mean of the numeric marks before and after this
    /// sitting's mark. Nil when the mark is already in the libretto, has no
    /// number, or the teaching's CFU are unknown.
    let meanImpact: MeanImpact?

    struct MeanImpact: Sendable, Equatable {
        let before: Double
        let after: Double
        let cfu: Int
        var delta: Double { after - before }
    }

    init(exam: ExamSession, sittings: [ExamSession], libretto: [LibrettoExam], now: Date) {
        // `isOf` compares the row's id against the sitting's code itself, so
        // the plain `==` that used to lead here added nothing — except that it
        // also matched two *blank* ids, handing this exam the first libretto
        // row that happened to have none.
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

    /// Only for a passed numeric mark not yet recorded: a recorded one is
    /// already in the mean, and a fail does not enter it.
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
