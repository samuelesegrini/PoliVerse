import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension ExamUpdate {
    /// What the feed would hold a few days into the September session, all of
    /// it about sittings that exist in ``ExamSession/samples(now:)``.
    ///
    /// Ordered newest first and spread over a week, so the feed shows its
    /// grouping, its unread marks and every delivery it can make.
    static func samples(now: Date = .now) -> [ExamUpdate] {
        let sessions = ExamSession.samples(now: now)
        /// The most recent sitting of a teaching, which is what an update is
        /// nearly always about.
        func session(_ code: String) -> ExamSession? {
            sessions.last { $0.courseCode == code }
        }
        func update(_ kind: ExamUpdate.Kind, _ code: String, hoursAgo: Double,
                    old: String? = nil, new: String? = nil,
                    delivery: ExamUpdate.Delivery = .inApp) -> ExamUpdate? {
            guard let session = session(code) else { return nil }
            return ExamUpdate(
                kind: kind, examID: session.id, courseCode: session.courseCode,
                courseName: session.courseName,
                detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: .exams,
                evidence: "iae:/v1/insegn c_appello=\(session.id)", oldValue: old, newValue: new,
                wasEnrolled: session.status == .enrolled || session.grade != nil,
                examDate: session.date, delivery: delivery)
        }
        func webeep(_ kind: ExamUpdate.Kind, _ code: String, hoursAgo: Double, new: String,
                    evidence: String, delivery: ExamUpdate.Delivery = .digest) -> ExamUpdate {
            let teaching = SampleDegree.teaching(code)
            return ExamUpdate(
                kind: kind, examID: nil, courseCode: teaching.code, courseName: teaching.name,
                detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: .webeep,
                evidence: evidence, newValue: new,
                wasEnrolled: session(code)?.status == .enrolled,
                examDate: session(code)?.date, delivery: delivery)
        }

        return [
            // The mark that just landed, and the window it opened.
            update(.gradePublished, "095946", hoursAgo: 5, new: "26", delivery: .urgent),
            update(.refusalOpened, "095946", hoursAgo: 5),
            update(.correctionsAvailable, "095946", hoursAgo: 4),
            // The sitting the day after tomorrow.
            update(.roomPublished, "091250", hoursAgo: 14, new: "Aula Magna Rogers", delivery: .push),
            webeep(.examNoticePosted, "091250", hoursAgo: 16,
                   new: "Istruzioni e materiale ammesso all'appello",
                   evidence: "webeep:mod_forum_get_forum_discussions", delivery: .push),
            // The window closing in four days.
            update(.enrolmentOpened, "089156", hoursAgo: 30, delivery: .digest),
            update(.roomChanged, "089156", hoursAgo: 34, old: "B.2.1", new: "Aula De Donato"),
            // The semester that has just started.
            webeep(.materialAdded, "095948", hoursAgo: 26, new: "Lezione 3 — diagrammi di sequenza",
                   evidence: "webeep:core_course_get_contents"),
            webeep(.assignmentAdded, "095948", hoursAgo: 48, new: "Progetto: consegna del documento di analisi",
                   evidence: "webeep:mod_assign_get_assignments"),
            webeep(.announcementPosted, "086657", hoursAgo: 52,
                   new: "Laboratorio di venerdì spostato in L.1.2",
                   evidence: "webeep:mod_forum_get_forum_discussions"),
            webeep(.solutionsPosted, "095857", hoursAgo: 70, new: "Soluzioni della prova in itinere",
                   evidence: "webeep:core_course_get_contents"),
            // Older, and already read by the time the student looks.
            update(.enrolled, "091250", hoursAgo: 96),
            update(.gradeRecorded, "095951", hoursAgo: 120),
            update(.discovered, "095948", hoursAgo: 150),
        ].compactMap { $0 }
    }
}

nonisolated extension Notice {
    static func samples(now: Date = .now) -> [Notice] {
        func notice(_ id: Int, _ title: String, _ body: String, _ category: String,
                    daysAgo: Double, read: Bool = false) -> Notice {
            Notice(id: "mock-\(id)", title: title, body: body,
                   date: now.addingTimeInterval(-daysAgo * 86_400), category: category,
                   serverRead: read, link: nil)
        }
        return [
            notice(1, "Esito disponibile: Basi di Dati",
                   "Il risultato dell'appello è consultabile sui Servizi Online. "
                       + "Il voto può essere rifiutato entro i termini indicati.",
                   "Carriera", daysAgo: 0.2),
            notice(2, "Aula dell'appello di Ricerca Operativa",
                   "L'appello di domani si tiene in Aula Magna Rogers. Presentarsi alle 8.45 con un documento.",
                   "Didattica", daysAgo: 0.6),
            notice(3, "Iscrizioni in scadenza",
                   "Le iscrizioni all'appello di Economia e Organizzazione Aziendale chiudono fra quattro giorni.",
                   "Carriera", daysAgo: 1.2),
            notice(4, "Scadenza seconda rata",
                   "Il pagamento della seconda rata dei contributi scade il 31 marzo. "
                       + "Il bollettino è disponibile nell'area Contributi.",
                   "Segreteria", daysAgo: 2),
            notice(5, "Questionario di valutazione della didattica",
                   "La compilazione è obbligatoria per iscriversi agli appelli del primo semestre.",
                   "Segreteria", daysAgo: 4, read: true),
            notice(6, "Aula cambiata per Reti di Calcolatori",
                   "Il laboratorio di venerdì si terrà in aula L.1.2.",
                   "Didattica", daysAgo: 6, read: true),
            notice(7, "Rinnovo del badge di ateneo",
                   "I badge scaduti si rinnovano allo sportello di Piazza Leonardo da Vinci 32.",
                   "Segreteria", daysAgo: 11, read: true),
        ]
    }
}

nonisolated extension NewsItem {
    static func samples(now: Date = .now) -> [NewsItem] {
        func news(_ id: Int, _ title: String, _ summary: String, _ category: String,
                  daysAgo: Double) -> NewsItem {
            NewsItem(id: "news-\(id)", title: title, summary: summary,
                     published: now.addingTimeInterval(-daysAgo * 86_400), expires: nil,
                     category: category, link: nil, imageURL: nil)
        }
        return [
            news(1, "Aperte le iscrizioni ai bandi di mobilità internazionale",
                 "Le candidature per lo scambio Erasmus+ si chiudono il 15 febbraio.",
                 "Internazionale", daysAgo: 1),
            news(2, "Nuovi spazi studio in Bovisa",
                 "Duecento posti in più, aperti fino alle 23 anche nel fine settimana.",
                 "Campus", daysAgo: 4),
            news(3, "Career Day di ateneo",
                 "Centoventi aziende in Campus Leonardo, giovedì e venerdì.",
                 "Lavoro", daysAgo: 5),
            news(4, "Seminario: intelligenza artificiale e ricerca",
                 "Aula Rogers, giovedì alle 17.",
                 "Eventi", daysAgo: 9),
            news(5, "Borse di collaborazione studentesca",
                 "Centocinquanta ore in biblioteca e nei laboratori. Domande entro fine mese.",
                 "Opportunità", daysAgo: 12),
            news(6, "Lavori sulla rete Wi-Fi di Edificio 21",
                 "Possibili interruzioni del servizio martedì mattina.",
                 "Campus", daysAgo: 15),
        ]
    }
}
