import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension CourseForum {
    static let samples = [
        CourseForum(id: 1, name: "Avvisi", kind: .announcements),
        CourseForum(id: 2, name: "Forum di discussione", kind: .discussion),
    ]
}

nonisolated extension MoodleDiscussion {
    static let samples = [
        MoodleDiscussion(id: 1, discussion: 1, name: nil, subject: "Spostamento appello del 10 giugno",
                         message: "Buongiorno, l'appello del 10 giugno è spostato al 12 giugno per indisponibilità dell'aula.",
                         created: Int(Date.now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970),
                         timemodified: nil, userfullname: "Prof. Marco Rossi", pinned: true),
        MoodleDiscussion(id: 2, discussion: 2, name: nil, subject: "Dubbio esercizio 4 - Assembly MIPS",
                         message: "Qualcuno ha capito come gestire il caso dell'overflow nell'esercizio 4?",
                         created: Int(Date.now.addingTimeInterval(-1 * 86_400).timeIntervalSince1970),
                         timemodified: nil, userfullname: "Giulia Bianchi", pinned: false),
    ]
}

nonisolated extension MoodlePosts.Post {
    static func samples(for discussion: MoodleDiscussion) -> [MoodlePosts.Post] {
        [MoodlePosts.Post(id: discussion.id, subject: discussion.subject, message: discussion.message,
                          timecreated: discussion.created, hasparent: false,
                          author: .init(fullname: discussion.userfullname))]
    }
}

nonisolated extension WeBeepSection {
    static func samples(for course: Course) -> [WeBeepSection] {
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
