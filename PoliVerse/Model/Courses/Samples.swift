import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension Course {
    static let samples: [Course]

    /// Named so that the other areas' samples can point at the same course
    /// instead of retyping its name and its code. Six copies of "Basi di Dati"
    /// written out by hand is how a demo drifts out of step with itself.
    static var architectures: Course { samples[0] }
    static var softwareEngineering: Course { samples[1] }
    static var geometry: Course { samples[2] }
    static var databases: Course { samples[3] }
    static var logicNetworks: Course { samples[4] }
    static var control: Course { samples[5] }
}

nonisolated extension Career {
    static func samples() -> [Career] {
        [
            Career(matricola: "986617", kind: "Laurea Triennale", status: "Chiusa"),
            Career(matricola: "332218", kind: "Laurea Magistrale", status: "Attiva"),
        ]
    }
}
