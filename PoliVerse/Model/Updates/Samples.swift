import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension ExamUpdate {
    /// What the updates feed would hold a few days into a session, matching
    /// ``examSessions(now:)``.
    static func samples(now: Date = .now) -> [ExamUpdate] {
        let sessions = ExamSession.samples(now: now)
        func update(_ kind: ExamUpdate.Kind, _ id: Int, hoursAgo: Double,
                    old: String? = nil, new: String? = nil,
                    delivery: ExamUpdate.Delivery = .inApp) -> ExamUpdate {
            let session = sessions.first { $0.id == id }!
            return ExamUpdate(
                kind: kind, examID: id, courseCode: session.courseCode,
                courseName: session.courseName,
                detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: .exams,
                evidence: "iae:/v1/insegn c_appello=\(id)", oldValue: old, newValue: new,
                wasEnrolled: session.status == .enrolled || session.grade != nil,
                examDate: session.date, delivery: delivery)
        }
        return [
            update(.gradePublished, 909, hoursAgo: 3, new: "24", delivery: .urgent),
            update(.refusalOpened, 909, hoursAgo: 3),
            update(.roomChanged, 901, hoursAgo: 20, old: "B.2.1", new: "Aula Magna", delivery: .digest),
            ExamUpdate(
                kind: .announcementPosted, examID: nil,
                courseCode: Course.softwareEngineering.id,
                courseName: Course.softwareEngineering.name, detectedAt: now.addingTimeInterval(-22 * 3600),
                source: .webeep, evidence: "webeep:mod_forum_get_forum_discussions",
                newValue: "Istruzioni per lo scritto del 25 settembre", wasEnrolled: true,
                examDate: sessions.first { $0.id == 901 }?.date, delivery: .push),
            update(.enrolmentOpened, 902, hoursAgo: 50, delivery: .digest),
            ExamUpdate(
                kind: .assignmentAdded, examID: nil, courseCode: Course.databases.id, courseName: Course.databases.name,
                detectedAt: now.addingTimeInterval(-30 * 3600), source: .webeep,
                evidence: "webeep:mod_assign_get_assignments", newValue: "Progetto: schema ER",
                wasEnrolled: false, examDate: now.addingTimeInterval(9 * 86400), delivery: .digest),
            update(.enrolled, 901, hoursAgo: 190),
            update(.roomPublished, 901, hoursAgo: 200, new: "B.2.1"),
            update(.discovered, 903, hoursAgo: 220),
        ]
    }
}

nonisolated extension Notice {
    static func samples(now: Date = .now) -> [Notice] {
        [
            Notice(id: "mock-1", title: "Esito disponibile: Analisi Matematica 2",
                   body: "Il risultato dell'appello del 12 gennaio è consultabile sui Servizi Online.",
                   date: now.addingTimeInterval(-3600 * 5), category: "Carriera",
                   serverRead: false, link: nil),
            Notice(id: "mock-2", title: "Scadenza seconda rata",
                   body: "Il pagamento della seconda rata scade il 31 marzo.",
                   date: now.addingTimeInterval(-86400 * 2), category: "Segreteria",
                   serverRead: false, link: nil),
            Notice(id: "mock-3", title: "Aula cambiata per Reti Logiche",
                   body: "La lezione di giovedì si terrà in aula 3.1.2.",
                   date: now.addingTimeInterval(-86400 * 6), category: "Didattica",
                   serverRead: true, link: nil),
        ]
    }
}

nonisolated extension NewsItem {
    static func samples(now: Date = .now) -> [NewsItem] {
        [
            NewsItem(id: "news-1", title: "Aperte le iscrizioni ai bandi di mobilità internazionale",
                     summary: "Le candidature per lo scambio Erasmus+ si chiudono il 15 febbraio.",
                     published: now.addingTimeInterval(-86400), expires: nil,
                     category: "Internazionale", link: nil, imageURL: nil),
            NewsItem(id: "news-2", title: "Nuovi spazi studio in Bovisa",
                     summary: "Duecento posti in più, aperti fino alle 23.",
                     published: now.addingTimeInterval(-86400 * 4), expires: nil,
                     category: "Campus", link: nil, imageURL: nil),
            NewsItem(id: "news-3", title: "Seminario: intelligenza artificiale e ricerca",
                     summary: "Aula Rogers, giovedì alle 17.",
                     published: now.addingTimeInterval(-86400 * 9), expires: nil,
                     category: "Eventi", link: nil, imageURL: nil),
        ]
    }
}
