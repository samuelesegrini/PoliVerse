import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Everything here is derived from ``SampleDegree`` rather than typed out.
/// The gradebook in particular is *computed* — the average the student sees
/// on Carriera is the same arithmetic Simulazione media runs on the same
/// libretto, so the two screens cannot drift apart. This ships: an incoherent
/// demo is something a student sees.

nonisolated extension LibrettoExam {
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

    /// What the libretto column says when there is no number to put there.
    private static func statusText(for teaching: SampleDegree.Teaching) -> String? {
        if teaching.isQualifying && teaching.isPassed { return "Idoneo" }
        if teaching.isPassed { return "Superato" }
        return teaching.attempts.isEmpty ? nil : "Non superato"
    }
}

nonisolated extension GradeBook {
    /// Computed from the libretto, never typed.
    ///
    /// The old sample carried a hand-written mean of 27.4 against 108 CFU
    /// while the libretto it sat beside added up to 27.16 against 55 — the
    /// same student with two careers, one per screen. There is now one
    /// source, and this is a reading of it.
    static var sample: GradeBook { sample(now: .now) }

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

nonisolated extension ExamSession {
    /// Every sitting: the ones already sat, one per attempt, and the ones
    /// this September's session is offering.
    ///
    /// Several attempts at one teaching are deliberate — they are what fills
    /// "Altre date" on the sitting's own page, and what lets the app show a
    /// mark refused or failed and then passed.
    static func samples(now: Date = .now) -> [ExamSession] {
        past(now: now) + upcoming(now: now)
    }

    // MARK: - Sat already

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

    /// One sitting in each state the app can draw, so the demo shows all of
    /// them: enrolled and imminent, open and closing, closed without
    /// enrolling, and not yet open.
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
            // The window shut and the student never enrolled — a state that
            // exists and that nothing else in the demo used to show.
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
