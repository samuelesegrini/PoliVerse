import Foundation

// Sample data for this area: what its screens show when the student chose
// "Esplora con dati di esempio", and what the previews render.
//
// Built from ``SampleDegree``, so a course's credits, teacher and code are
// the plan's — the course page and the libretto cannot disagree about Basi
// di Dati being worth 10 CFU. This ships: an incoherent demo is something a
// student sees.

/// The sample courses shown under ``Session/useMockData`` and in previews.
///
/// Derived from ``SampleDegree``, so a course's credits, lecturer and code are the
/// plan's and the course page cannot disagree with the libretto.
nonisolated extension Course {
    /// ``samples(now:)`` against the current date.
    static var samples: [Course] { samples(now: .now) }

    /// One course per teaching with material worth showing: the semester now running,
    /// plus the two of last year still to be sat and the one whose mark has just
    /// arrived.
    ///
    /// - Parameter now: The date the academic years are derived against.
    /// - Returns: The sample courses, each with a `moodleID` so that the materials
    ///   screens work.
    static func samples(now: Date = .now) -> [Course] {
        let shown = SampleDegree.currentTeachings
            + ["089156", "091250", "095946"].map(SampleDegree.teaching)
        return shown.enumerated().map { index, teaching in
            var course = Course(
                id: teaching.code,
                name: teaching.name,
                teacher: teaching.teacher,
                cfu: teaching.cfu,
                semester: String(teaching.semester),
                academicYear: SampleDegree.academicYear(for: teaching, now: now)
            )
            course.code = teaching.code
            course.moodleID = 1000 + index
            return course
        }
    }

    /// Ingegneria del Software, for the other areas' samples to point at.
    static var softwareEngineering: Course { sample("095948") }
    /// Reti di Calcolatori.
    static var networks: Course { sample("086657") }
    /// Controlli Automatici.
    static var control: Course { sample("095857") }
    /// Basi di Dati.
    static var databases: Course { sample("095946") }
    /// Economia.
    static var economics: Course { sample("089156") }
    /// Ricerca Operativa.
    static var operationsResearch: Course { sample("091250") }

    /// The sample course with a given teaching code.
    ///
    /// - Parameter code: The teaching code, which must be one ``samples`` contains.
    /// - Returns: The course.
    private static func sample(_ code: String) -> Course {
        samples.first { $0.id == code }!
    }
}

/// The sample enrolment.
nonisolated extension Career {
    /// A single active triennale, matching ``Student/sample``'s matricola.
    ///
    /// - Returns: The sample enrolments.
    static func samples() -> [Career] {
        [
            Career(matricola: "986617", kind: "Laurea Triennale", status: "Attiva"),
        ]
    }
}
