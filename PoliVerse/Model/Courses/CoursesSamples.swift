import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Built from ``SampleDegree``, so a course's credits, teacher and code are
/// the plan's — the course page and the libretto cannot disagree about Basi
/// di Dati being worth 10 CFU. This ships: an incoherent demo is something a
/// student sees.

nonisolated extension Course {
    /// One WeBeep course per teaching with material worth showing: the
    /// semester now running, plus the two of last year still to be sat and
    /// the one whose mark just arrived.
    static var samples: [Course] { samples(now: .now) }

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

    /// Named so that the other areas' samples can point at the same course
    /// instead of retyping its name and its code. Six copies of "Basi di Dati"
    /// written out by hand is how a demo drifts out of step with itself.
    static var softwareEngineering: Course { sample("095948") }
    static var networks: Course { sample("086657") }
    static var control: Course { sample("095857") }
    static var databases: Course { sample("095946") }
    static var economics: Course { sample("089156") }
    static var operationsResearch: Course { sample("091250") }

    private static func sample(_ code: String) -> Course {
        samples.first { $0.id == code }!
    }
}

nonisolated extension Career {
    static func samples() -> [Career] {
        [
            Career(matricola: "986617", kind: "Laurea Triennale", status: "Attiva"),
        ]
    }
}
