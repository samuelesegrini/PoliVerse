import Foundation

// Sample data for this area: what its screens show when the student chose
// "Esplora con dati di esempio", and what the previews render.
//
// Built from ``SampleDegree``: a course's files are about that course, its
// assignments are the plan's assignments, and its forum talks about the
// sitting the career actually has. This ships — an incoherent demo is
// something a student sees.

/// The sample forums: one for announcements, one for discussion.
nonisolated extension CourseForum {
    /// An announcements forum and a discussion forum.
    static let samples = [
        CourseForum(id: 1, name: "Avvisi del docente", kind: .announcements),
        CourseForum(id: 2, name: "Forum di discussione", kind: .discussion),
    ]
}

/// The sample forum discussions.
nonisolated extension MoodleDiscussion {
    /// ``samples(now:)`` against the current date.
    static var samples: [MoodleDiscussion] { samples(now: .now) }

    /// Threads for the course the sample student is about to sit, so the forum says
    /// something that matches the rest of the sample data.
    ///
    /// - Parameter now: The date the threads are dated back from.
    /// - Returns: The discussions.
    static func samples(now: Date = .now) -> [MoodleDiscussion] {
        func created(_ daysAgo: Double) -> Int {
            Int(now.addingTimeInterval(-daysAgo * 86_400).timeIntervalSince1970)
        }
        return [
            MoodleDiscussion(id: 1, discussion: 1, name: nil,
                             subject: "Istruzioni per l'appello di domani",
                             message: "L'appello si tiene in Aula Magna Rogers alle 9.00. "
                                 + "Portate un documento e la calcolatrice; non è ammesso altro materiale.",
                             created: created(0.7), timemodified: nil,
                             userfullname: "Prof. Edoardo Amaldi", pinned: true),
            MoodleDiscussion(id: 2, discussion: 2, name: nil,
                             subject: "Ricevimento spostato a giovedì",
                             message: "Il ricevimento di mercoledì è spostato a giovedì 14.30, stanza 3.2.7.",
                             created: created(2), timemodified: nil,
                             userfullname: "Prof. Edoardo Amaldi", pinned: false),
            MoodleDiscussion(id: 3, discussion: 3, name: nil,
                             subject: "Dubbio esercizio 4 — rilassamento continuo",
                             message: "Qualcuno ha capito perché il rilassamento continuo dà un bound "
                                 + "più debole quando i vincoli non sono in forma standard?",
                             created: created(3.5), timemodified: nil,
                             userfullname: "Giulia Bianchi", pinned: false),
            MoodleDiscussion(id: 4, discussion: 4, name: nil,
                             subject: "Gruppo di studio per il progetto",
                             message: "Cerchiamo un quarto per il gruppo del progetto. Scriveteci qui.",
                             created: created(6), timemodified: nil,
                             userfullname: "Luca Moretti", pinned: false),
        ]
    }
}

/// The sample posts within a discussion.
nonisolated extension MoodlePosts.Post {
    /// A thread with replies, so the discussion view is not always a single post.
    ///
    /// - Parameter discussion: The discussion to build a thread for.
    /// - Returns: The opening post and its replies, oldest first. A pinned discussion gets
    ///   the opening post alone.
    static func samples(for discussion: MoodleDiscussion) -> [MoodlePosts.Post] {
        let opening = MoodlePosts.Post(
            id: discussion.id * 100, subject: discussion.subject, message: discussion.message,
            timecreated: discussion.created, hasparent: false,
            author: .init(fullname: discussion.userfullname))
        guard discussion.pinned != true else { return [opening] }

        let replies: [(String, String, Double)] = switch discussion.id {
        case 3: [("Matteo Pradella", "Il bound è più debole perché il poliedro rilassato è più grande: "
                  + "prova a disegnare il caso in due variabili.", 2.5),
                 ("Giulia Bianchi", "Chiarissimo, grazie!", 2.2)]
        case 4: [("Sara Conti", "Io ci sto, ho già fatto la parte di analisi l'anno scorso.", 5)]
        default: []
        }
        return [opening] + replies.enumerated().map { index, reply in
            MoodlePosts.Post(
                id: discussion.id * 100 + index + 1,
                subject: "Re: " + (discussion.subject ?? ""), message: reply.1,
                timecreated: (discussion.created ?? 0) + Int(reply.2 * 3600),
                hasparent: true, author: .init(fullname: reply.0))
        }
    }
}

/// The sample assignment deadlines.
nonisolated extension AssignmentDeadline {
    /// The work outstanding on WeBeep, soonest first, from ``SampleDegree``'s assignments.
    ///
    /// Only deadlines still ahead are included, and each closes at the end of its day as
    /// WeBeep's do.
    ///
    /// - Parameter now: The date the offsets are measured from.
    /// - Returns: The deadlines.
    static func samples(now: Date = .now) -> [AssignmentDeadline] {
        var id = 500
        return SampleDegree.teachings.flatMap { teaching in
            teaching.assignments.compactMap { assignment -> AssignmentDeadline? in
                id += 1
                let due = now.addingTimeInterval(assignment.dueInDays * 86_400)
                // Only what is still ahead: a closed hand-in is not a deadline.
                guard due > now else { return nil }
                return AssignmentDeadline(
                    id: id, courseCode: teaching.code, courseName: teaching.name,
                    name: assignment.name,
                    // Hand-ins close at the end of the day, as WeBeep's do.
                    due: PoliMiDate.romeCalendar.date(
                        bySettingHour: 23, minute: 59, second: 0, of: due) ?? due)
            }
        }
        .sorted { $0.due < $1.due }
    }
}

/// The sample course materials.
nonisolated extension WeBeepSection {
    /// A course's material, drawn from its own lecture topics in ``SampleDegree``, so two
    /// courses do not show the same files.
    ///
    /// - Parameters:
    ///   - course: The course to build material for.
    ///   - now: The date the files' modification times are measured back from.
    /// - Returns: The sections, each with its files.
    static func samples(for course: Course, now: Date = .now) -> [WeBeepSection] {
        let teaching = SampleDegree.teachings.first { $0.code == course.id }
        let topics = teaching?.topics ?? []

        func file(_ name: String, _ section: String, _ mb: Double, _ daysAgo: Double) -> WeBeepFile {
            WeBeepFile(
                id: "\(course.id)-\(name)",
                name: name,
                courseID: course.id,
                sectionName: section,
                sizeBytes: Int(mb * 1_048_576),
                modifiedAt: now.addingTimeInterval(-daysAgo * 86_400),
                downloadURL: nil
            )
        }

        var sections: [WeBeepSection] = [
            WeBeepSection(id: "\(course.id)-info", name: "Informazioni generali", files: [
                file("Programma del corso.pdf", "Informazioni generali", 0.4, 40),
                file("Modalità d'esame.pdf", "Informazioni generali", 0.2, 38),
                file("Bibliografia e testi consigliati.pdf", "Informazioni generali", 0.3, 38),
            ]),
        ]

        if !topics.isEmpty {
            // Newest last, one lecture every few days, the most recent still
            // fresh enough to be marked as new.
            let lectures = topics.enumerated().map { index, topic in
                file(String(format: "%02d", index + 1) + " - \(topic).pdf", "Lezioni",
                     2.4 + Double(index) * 0.8, Double(topics.count - index) * 3.5)
            }
            let recording = file("Registrazione lezione \(String(format: "%02d", topics.count)).mp4",
                                 "Lezioni", 218, 3.5)
            sections.append(WeBeepSection(id: "\(course.id)-lectures", name: "Lezioni",
                                          files: lectures + [recording]))
            sections.append(WeBeepSection(id: "\(course.id)-exercises", name: "Esercitazioni", files: [
                file("Esercizi svolti — \(topics.first ?? "introduzione").pdf", "Esercitazioni", 1.9, 22),
                file("Temi d'esame degli anni scorsi.pdf", "Esercitazioni", 2.4, 9),
                file("Soluzioni commentate.pdf", "Esercitazioni", 1.6, 8),
                file("Codice delle esercitazioni.zip", "Esercitazioni", 14.7, 9),
            ]))
        }

        if let teaching, !teaching.assignments.isEmpty {
            sections.append(WeBeepSection(id: "\(course.id)-assignments", name: "Consegne", files: [
                file("Specifica della consegna.pdf", "Consegne", 0.6, 12),
                file("Template LaTeX.zip", "Consegne", 0.9, 12),
            ]))
        }
        return sections
    }
}
