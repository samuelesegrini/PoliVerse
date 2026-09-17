import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension GradeBook {
    /// A plausible teaching week: lectures Monday to Friday, an exam, and a
    /// deadline. Anchored to the week containing `date` so the calendar always
    /// has something to show whenever it is opened.
    static let sample = GradeBook(
        mean: 27.4, earnedCFU: 108, plannedCFU: 180,
        examsPlanned: 22, examsSubscribed: 2, examsGiven: 14
    )
}

nonisolated extension LibrettoExam {
    static func samples(now: Date = .now) -> [LibrettoExam] {
        func exam(_ id: String, _ name: String, _ grade: Int?, _ cfu: Int,
                  _ daysAgo: Int?, lode: Bool = false) -> LibrettoExam {
            LibrettoExam(
                id: id, name: name, grade: grade, hasLode: lode, cfu: cfu,
                date: daysAgo.map { now.addingTimeInterval(TimeInterval(-$0 * 86_400)) },
                statusText: daysAgo == nil ? nil : "Superato",
                isPassed: daysAgo != nil
            )
        }
        return [
            exam("086088", "Analisi e Geometria 1", 30, 10, 640, lode: true),
            exam(Course.logicNetworks.id, Course.logicNetworks.name, 28, 5, 520),
            exam("083801", "Fisica Sperimentale", 25, 8, 430),
            exam("083802", "Chimica", 27, 6, 360),
            exam("085923", "Architetture dei Calcolatori", 26, 10, 250),
            exam(Course.geometry.id, Course.geometry.name, 24, 8, 160),
            exam("084392", "Informatica Teorica", 30, 8, 90),
            exam(Course.databases.id, Course.databases.name, nil, 8, nil),
            exam(Course.softwareEngineering.id, Course.softwareEngineering.name, nil, 12, nil),
        ]
    }
}

nonisolated extension ExamSession {
    static func samples(now: Date = .now) -> [ExamSession] {
        let calendar = PoliMiDate.romeCalendar
        func day(_ offset: Int, hour: Int = 9) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0,
                          of: calendar.date(byAdding: .day, value: offset, to: now)!)!
        }

        func graded(_ id: Int, _ name: String, _ code: String, _ mark: Int,
                    _ daysAgo: Int, lode: Bool = false) -> ExamSession {
            ExamSession(
                id: id, courseName: name, courseCode: code, teacher: nil,
                date: day(-daysAgo), room: nil,
                enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
                kind: "Scritto",
                status: .graded(ExamGrade(
                    value: mark,
                    text: lode ? "30 e lode" : String(mark),
                    passed: mark >= 18,
                    refusable: daysAgo < 7
                ))
            )
        }

        return [
            ExamSession(
                id: 901, courseName: Course.softwareEngineering.name, courseCode: Course.softwareEngineering.id,
                teacher: "Matteo Rossi", date: day(12, hour: 9), room: "Aula Magna",
                enrolmentOpens: day(-8), enrolmentCloses: day(5),
                enrolledCount: 214, kind: "Scritto", status: .enrolled
            ),
            ExamSession(
                id: 902, courseName: Course.databases.name, courseCode: Course.databases.id,
                teacher: "Stefano Ceri", date: day(19, hour: 14), room: "Aula Rogers",
                enrolmentOpens: day(-2), enrolmentCloses: day(12),
                enrolledCount: 158, kind: "Scritto e orale", status: .open
            ),
            ExamSession(
                id: 903, courseName: Course.control.name, courseCode: Course.control.id,
                teacher: "Luigi Piroddi", date: day(34, hour: 9), room: nil,
                enrolmentOpens: day(14), enrolmentCloses: day(30),
                enrolledCount: 0, kind: "Scritto", status: .notYetOpen
            ),
            graded(904, "Analisi e Geometria 1", "086088", 30, 190, lode: true),
            graded(905, Course.logicNetworks.name, Course.logicNetworks.id, 28, 150),
            graded(906, "Fisica Sperimentale", "083801", 25, 120),
            graded(907, "Chimica", "083802", 27, 95),
            graded(908, "Informatica Teorica", "084392", 30, 40),
            graded(909, Course.geometry.name, Course.geometry.id, 24, 5),
        ]
    }
}
