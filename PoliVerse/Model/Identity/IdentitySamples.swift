import Foundation

// Sample data for this area: what its screens show when the student chose
// "Esplora con dati di esempio", and what the previews render.
//
// Real names from an Ingegneria Informatica plan, so layout is tested against
// realistic string lengths rather than "Lorem ipsum". This ships — an
// incoherent demo is something a student sees.

/// The sample student shown under ``Session/useMockData`` and in previews.
nonisolated extension Student {
    /// A representative student, with realistic name and address lengths so that layout
    /// is exercised against real strings.
    static let sample = Student(
        personCode: "10659812",
        matricola: "986617",
        firstName: "Samuele",
        lastName: "Segrini",
        email: "samuele.segrini@mail.polimi.it",
        photoURL: nil
    )
}
