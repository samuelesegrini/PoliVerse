import Foundation

/// Representative data so every screen renders before the endpoints are wired.
/// Real course names from an Ingegneria Informatica plan, so layout is tested
/// against realistic string lengths rather than "Lorem ipsum".
nonisolated enum MockData {
    static let student = Student(
        personCode: "10659812",
        matricola: "986617",
        firstName: "Samuele",
        lastName: "Segrini",
        email: "samuele.segrini@mail.polimi.it",
        photoURL: nil
    )

    static let courses: [Course] = [
        Course(id: "085923", name: "Architetture dei Calcolatori e Sistemi Operativi",
               teacher: "Cristina Silvano", cfu: 10, semester: "1", academicYear: "2025"),
        Course(id: "089160", name: "Ingegneria del Software",
               teacher: "Matteo Rossi", cfu: 12, semester: "2", academicYear: "2025"),
        Course(id: "086089", name: "Analisi e Geometria 2",
               teacher: "Federico Lastaria", cfu: 8, semester: "1", academicYear: "2025"),
        Course(id: "097785", name: "Basi di Dati",
               teacher: "Stefano Ceri", cfu: 8, semester: "2", academicYear: "2025"),
        Course(id: "084391", name: "Reti Logiche",
               teacher: "Fabio Salice", cfu: 5, semester: "1", academicYear: "2025"),
        Course(id: "091252", name: "Fondamenti di Automatica",
               teacher: "Luigi Piroddi", cfu: 8, semester: "2", academicYear: "2025"),
    ]

    static func weBeepSections(for course: Course) -> [WeBeepSection] {
        let base = Date.now
        func file(_ name: String, _ section: String, _ mb: Double, _ daysAgo: Int) -> WeBeepFile {
            WeBeepFile(
                id: "\(course.id)-\(name)",
                name: name,
                courseID: course.id,
                sectionName: section,
                sizeBytes: Int(mb * 1_048_576),
                modifiedAt: base.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
                downloadURL: nil
            )
        }
        return [
            WeBeepSection(id: "\(course.id)-info", name: "Informazioni generali", files: [
                file("Programma del corso.pdf", "Informazioni generali", 0.4, 40),
                file("Modalità d'esame.pdf", "Informazioni generali", 0.2, 38),
            ]),
            WeBeepSection(id: "\(course.id)-lectures", name: "Lezioni", files: [
                file("01 - Introduzione.pdf", "Lezioni", 3.2, 30),
                file("02 - Rappresentazione dell'informazione.pdf", "Lezioni", 5.8, 26),
                file("03 - Assembly MIPS.pdf", "Lezioni", 7.1, 19),
                file("04 - Pipeline e hazard.pdf", "Lezioni", 6.4, 12),
                file("Registrazione lezione 04.mp4", "Lezioni", 218.0, 12),
            ]),
            WeBeepSection(id: "\(course.id)-exercises", name: "Esercitazioni", files: [
                file("Esercizi svolti - Assembly.pdf", "Esercitazioni", 1.9, 22),
                file("Soluzioni tema d'esame 2024.pdf", "Esercitazioni", 2.4, 9),
                file("Codice esercitazioni.zip", "Esercitazioni", 14.7, 9),
            ]),
        ]
    }
}
