import Foundation

// Sample data for this area: what its screens show when the student chose
// "Esplora con dati di esempio", and what the previews render.
//
// Everything here is derived from ``SampleDegree`` rather than typed out.
// The gradebook in particular is *computed* — the average the student sees
// on Carriera is the same arithmetic Simulazione media runs on the same
// libretto, so the two screens cannot drift apart. This ships: an incoherent
// demo is something a student sees.

/// The sample libretto, derived from ``SampleDegree``.
nonisolated extension LibrettoExam {
    /// One row per teaching in the sample degree, dated from its passing attempt.
    ///
    /// - Parameter now: The date the attempt offsets are measured back from.
    /// - Returns: The rows. An unpassed teaching has no date.
    static func samples(now: Date = .now) -> [LibrettoExam] {
        SampleDegree.teachings.map { teaching in
            let attempt = teaching.passingAttempt ?? teaching.attempts.last
            return LibrettoExam(
                id: teaching.code,
                name: teaching.name,
                grade: teaching.mark,
                hasLode: teaching.hasLode,
                cfu: teaching.cfu,
                date: teaching.isPassed
                    ? attempt.map { SampleDegree.date(monthsAgo: $0.monthsAgo, now: now) }
                    : nil,
                statusText: statusText(for: teaching),
                isPassed: teaching.isPassed
            )
        }
    }

    /// What the libretto's status column says when there is no mark to show.
    ///
    /// - Parameter teaching: The teaching to describe.
    /// - Returns: `"Idoneo"` for a passed pass/fail teaching, `"Superato"` for any other
    ///   pass, `"Non superato"` for a failed attempt, and `nil` for a teaching never
    ///   attempted.
    private static func statusText(for teaching: SampleDegree.Teaching) -> String? {
        if teaching.isQualifying && teaching.isPassed { return "Idoneo" }
        if teaching.isPassed { return "Superato" }
        return teaching.attempts.isEmpty ? nil : "Non superato"
    }
}

/// The sample aggregate figures, computed from the sample libretto rather than typed
/// out — so Carriera and Simulazione media cannot disagree about the same student.
nonisolated extension GradeBook {
    /// ``sample(now:)`` against the current date.
    static var sample: GradeBook { sample(now: .now) }

    /// The figures a reading of the sample libretto produces.
    ///
    /// - Parameter now: The date the sample libretto is dated against.
    /// - Returns: The grade book.
    static func sample(now: Date = .now) -> GradeBook {
        let plan = StudyPlan(exams: LibrettoExam.samples(now: now))
        let teachings = SampleDegree.teachings
        return GradeBook(
            mean: plan.weightedMean ?? 0,
            earnedCFU: plan.earnedCFU,
            plannedCFU: SampleDegree.plannedCFU,
            examsPlanned: teachings.count,
            examsSubscribed: ExamSession.samples(now: now).filter { $0.status == .enrolled }.count,
            examsGiven: teachings.filter(\.isPassed).count
        )
    }
}

/// The sample exam sittings.
nonisolated extension ExamSession {
    /// Every sample sitting: one per past attempt, plus the session currently open.
    ///
    /// Several attempts at one teaching are deliberate — they fill “Altre date” on a
    /// sitting's page, and let the app show a mark refused or failed and then passed.
    ///
    /// - Parameter now: The date the offsets are measured from.
    /// - Returns: The sittings.
    static func samples(now: Date = .now) -> [ExamSession] {
        past(now: now) + upcoming(now: now)
    }

    // MARK: - Sat already

    /// One marked sitting per recorded attempt in the sample degree.
    ///
    /// A mark is refusable only for a few days after it appears, and only the most recent
    /// sitting still has a script to inspect.
    ///
    /// - Parameter now: The date the offsets are measured back from.
    /// - Returns: The marked sittings.
    private static func past(now: Date = .now) -> [ExamSession] {
        var id = 900
        return SampleDegree.teachings.flatMap { teaching -> [ExamSession] in
            teaching.attempts.map { attempt in
                id += 1
                let date = SampleDegree.date(monthsAgo: attempt.monthsAgo, now: now)
                // A mark can only be refused for a few days after it appears.
                let days = now.timeIntervalSince(date) / 86_400
                var session = ExamSession(
                    id: id, courseName: teaching.name, courseCode: teaching.code,
                    teacher: teaching.teacher, date: date, room: nil,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
                    kind: teaching.assessment.rawValue,
                    status: .graded(grade(for: attempt, teaching: teaching, daysSince: days))
                )
                // Only the most recent sitting still has a paper to look at.
                session.hasCorrections = days < 14 && attempt.mark != nil
                return session
            }
        }
    }

    /// The published result for one sample attempt.
    ///
    /// - Parameters:
    ///   - attempt: The attempt to describe.
    ///   - teaching: The teaching it belongs to, which decides whether the result is
    ///     pass/fail.
    ///   - daysSince: How long ago the mark appeared, which decides whether it is still
    ///     refusable.
    /// - Returns: The result.
    private static func grade(for attempt: SampleDegree.Attempt,
                              teaching: SampleDegree.Teaching,
                              daysSince: Double) -> ExamGrade {
        if teaching.isQualifying {
            return ExamGrade(value: nil, text: "Idoneo", passed: true, refusable: false)
        }
        let mark = attempt.mark ?? 0
        return ExamGrade(
            value: attempt.mark,
            text: attempt.lode ? "30 e lode" : String(mark),
            passed: attempt.passed,
            // Only a mark that stands can be refused, and only while the
            // window is open.
            refusable: attempt.passed && daysSince < 7
        )
    }

    // MARK: - The session now open

    /// One sitting in each state the app can draw: enrolled and imminent, open and
    /// closing, closed without enrolling, and not yet open.
    ///
    /// - Parameter now: The date the offsets are measured from.
    /// - Returns: The upcoming sittings.
    private static func upcoming(now: Date = .now) -> [ExamSession] {
        let calendar = PoliMiDate.romeCalendar
        func day(_ offset: Int, hour: Int = 9, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func sitting(_ id: Int, _ code: String, date: Date, room: String?,
                     opens: Date?, closes: Date?, enrolled: Int?,
                     status: ExamStatus) -> ExamSession {
            let teaching = SampleDegree.teaching(code)
            return ExamSession(
                id: id, courseName: teaching.name, courseCode: teaching.code,
                teacher: teaching.teacher, date: date, room: room,
                enrolmentOpens: opens, enrolmentCloses: closes, enrolledCount: enrolled,
                kind: teaching.assessment.rawValue, status: status
            )
        }

        return [
            // Enrolled, tomorrow morning: Adesso only counts down a sitting
            // inside 48 hours, and "the day after tomorrow at nine" is past
            // that for most of the day.
            sitting(801, "091250", date: day(1, hour: 9), room: "Aula Magna Rogers",
                    opens: day(-21), closes: day(-4), enrolled: 187, status: .enrolled),
            // Open, closing in four days: Adesso's enrolment card.
            sitting(802, "089156", date: day(11, hour: 14, minute: 30), room: "Aula De Donato",
                    opens: day(-6), closes: day(4), enrolled: 62, status: .open),
            // The window shut and the student never enrolled: a real state,
            // and the only sitting in the demo that shows it.
            sitting(803, "091250", date: day(16, hour: 9), room: nil,
                    opens: day(-30), closes: day(-9), enrolled: 94, status: .closed),
            // January, still months off.
            sitting(804, "095948", date: day(112, hour: 9), room: nil,
                    opens: day(82), closes: day(105), enrolled: 0, status: .notYetOpen),
            sitting(805, "086657", date: day(119, hour: 14), room: nil,
                    opens: day(89), closes: day(112), enrolled: 0, status: .notYetOpen),
            sitting(806, "095857", date: day(126, hour: 9), room: nil,
                    opens: day(96), closes: day(119), enrolled: 0, status: .notYetOpen),
        ]
    }
}
