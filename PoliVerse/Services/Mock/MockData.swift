import CoreLocation
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

    /// A plausible teaching week: lectures Monday to Friday, an exam, and a
    /// deadline. Anchored to the week containing `date` so the calendar always
    /// has something to show whenever it is opened.
    static let gradeBook = GradeBook(
        mean: 27.4, earnedCFU: 108, plannedCFU: 180,
        examsPlanned: 22, examsSubscribed: 2, examsGiven: 14
    )

    static func libretto(now: Date = .now) -> [LibrettoExam] {
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
            exam("084391", "Reti Logiche", 28, 5, 520),
            exam("083801", "Fisica Sperimentale", 25, 8, 430),
            exam("083802", "Chimica", 27, 6, 360),
            exam("085923", "Architetture dei Calcolatori", 26, 10, 250),
            exam("086089", "Analisi e Geometria 2", 24, 8, 160),
            exam("084392", "Informatica Teorica", 30, 8, 90),
            exam("097785", "Basi di Dati", nil, 8, nil),
            exam("089160", "Ingegneria del Software", nil, 12, nil),
        ]
    }

    static func examSessions(now: Date = .now) -> [ExamSession] {
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
                id: 901, courseName: "Ingegneria del Software", courseCode: "089160",
                teacher: "Matteo Rossi", date: day(12, hour: 9), room: "Aula Magna",
                enrolmentOpens: day(-8), enrolmentCloses: day(5),
                enrolledCount: 214, kind: "Scritto", status: .enrolled
            ),
            ExamSession(
                id: 902, courseName: "Basi di Dati", courseCode: "097785",
                teacher: "Stefano Ceri", date: day(19, hour: 14), room: "Aula Rogers",
                enrolmentOpens: day(-2), enrolmentCloses: day(12),
                enrolledCount: 158, kind: "Scritto e orale", status: .open
            ),
            ExamSession(
                id: 903, courseName: "Fondamenti di Automatica", courseCode: "091252",
                teacher: "Luigi Piroddi", date: day(34, hour: 9), room: nil,
                enrolmentOpens: day(14), enrolmentCloses: day(30),
                enrolledCount: 0, kind: "Scritto", status: .notYetOpen
            ),
            graded(904, "Analisi e Geometria 1", "086088", 30, 190, lode: true),
            graded(905, "Reti Logiche", "084391", 28, 150),
            graded(906, "Fisica Sperimentale", "083801", 25, 120),
            graded(907, "Chimica", "083802", 27, 95),
            graded(908, "Informatica Teorica", "084392", 30, 40),
            graded(909, "Analisi e Geometria 2", "086089", 24, 5),
        ]
    }

    /// What the updates feed would hold a few days into a session, matching
    /// ``examSessions(now:)``.
    static func examUpdates(now: Date = .now) -> [ExamUpdate] {
        let sessions = examSessions(now: now)
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
            update(.enrolmentOpened, 902, hoursAgo: 50, delivery: .digest),
            update(.enrolled, 901, hoursAgo: 190),
            update(.roomPublished, 901, hoursAgo: 200, new: "B.2.1"),
            update(.discovered, 903, hoursAgo: 220),
        ]
    }

    static func agendaEvents(around date: Date) -> [AgendaEvent] {
        let calendar = PoliMiDate.romeCalendar
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)

        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        var id = 1
        func event(
            _ title: String, _ dayOffset: Int, _ startHour: Int, _ endHour: Int,
            _ kind: EventKind = .lecture, room: String? = nil, acronym: String? = nil
        ) -> AgendaEvent {
            defer { id += 1 }
            return AgendaEvent(
                id: id,
                title: title,
                start: at(dayOffset, startHour, 15),
                end: at(dayOffset, endHour, 0),
                kind: kind,
                room: room,
                roomAcronym: acronym,
                calendarName: "Ingegneria Informatica"
            )
        }

        /// A deadline is a moment, not a span.
        func deadline(_ title: String, _ dayOffset: Int, _ hour: Int, _ minute: Int) -> AgendaEvent {
            defer { id += 1 }
            let moment = at(dayOffset, hour, minute)
            return AgendaEvent(
                id: id, title: title, start: moment, end: moment,
                kind: .deadline, calendarName: "Ingegneria Informatica"
            )
        }

        return [
            event("Analisi e Geometria 2", 0, 8, 10, room: "Aula Rogers", acronym: "R.0.1"),
            event("Architetture dei Calcolatori", 0, 10, 13, room: "Aula De Donato", acronym: "D.0.2"),
            event("Basi di Dati", 1, 9, 12, room: "Aula Castigliano", acronym: "C.1.1"),
            event("Reti Logiche", 1, 14, 16, room: "Aula Alfa", acronym: "A.2.3"),
            event("Fondamenti di Automatica", 2, 8, 11, room: "Aula Rogers", acronym: "R.0.1"),
            event("Ingegneria del Software", 2, 14, 17, room: "Aula Beta", acronym: "B.1.4"),
            deadline("Consegna progetto IS", 2, 23, 59),
            event("Basi di Dati — esercitazione", 3, 10, 13, room: "Lab Informatico", acronym: "L.0.5"),
            event("Architetture dei Calcolatori", 4, 9, 12, room: "Aula De Donato", acronym: "D.0.2"),
            event("Prova in itinere — Analisi 2", 4, 14, 16, .exam, room: "Aula Magna", acronym: "M.0.1"),
        ]
    }

    static func notices(now: Date = .now) -> [Notice] {
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

    static func news(now: Date = .now) -> [NewsItem] {
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

    static func auleSites() -> [AuleSite] {
        [
            AuleSite(id: "MIA", name: "Milano Leonardo"),
            AuleSite(id: "MIB", name: "Milano Bovisa"),
        ]
    }

    static func roomSchedules(on day: Date) -> [RoomSchedule] {
        let calendar = PoliMiDate.romeCalendar
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return [
            RoomSchedule(id: "3.0.1", name: "Aula 3.0.1", building: "Edificio 3",
                         seats: 120, bookings: [
                             RoomBooking(id: "a", start: at(8, 15), end: at(10, 15),
                                         title: "Analisi Matematica 2"),
                             RoomBooking(id: "b", start: at(14), end: at(16),
                                         title: "Fisica Tecnica"),
                         ]),
            RoomSchedule(id: "2.1.4", name: "Aula 2.1.4", building: "Edificio 2",
                         seats: 80, bookings: [
                             RoomBooking(id: "c", start: at(10, 15), end: at(13, 15),
                                         title: "Reti Logiche"),
                         ]),
            RoomSchedule(id: "B.2.2", name: "Aula B.2.2", building: "Edificio B",
                         seats: 60, bookings: []),
        ]
    }

    static func careers() -> [Career] {
        [
            Career(matricola: "986617", kind: "Laurea Triennale", status: "Chiusa"),
            Career(matricola: "332218", kind: "Laurea Magistrale", status: "Attiva"),
        ]
    }

    static func classrooms() -> [Classroom] {
        [
            Classroom(id: "3.0.1", capacity: 120, buildingCode: "MIA0103",
                      floorCode: "MIA0103000", buildingName: "Edificio 3",
                      floorName: "Piano terra", campusName: "Milano Leonardo",
                      address: "Piazza Leonardo da Vinci 32, Milano",
                      accessibleSeats: 4, occupancyID: "32",
                      roomCode: "MIA0103000001"),
            Classroom(id: "2.1.4", capacity: 80, buildingCode: "MIA0102",
                      floorCode: "MIA0102001", buildingName: "Edificio 2",
                      floorName: "Primo piano", campusName: "Milano Leonardo",
                      address: "Piazza Leonardo da Vinci 32, Milano",
                      occupancyID: "67", roomCode: "MIA0102001004"),
            Classroom(id: "B.2.2", capacity: 60, buildingCode: "MIB0202",
                      floorCode: "MIB0202002", buildingName: "Edificio B2",
                      floorName: "Secondo piano", campusName: "Milano Bovisa",
                      address: "Via Candiani 72, Milano",
                      occupancyID: "1541", roomCode: "MIB0202002002"),
        ]
    }

    static func facilities() -> [RoomFacility] {
        [
            RoomFacility(id: 4, it: "Video proiettore", en: "Video projector"),
            RoomFacility(id: 5, it: "Radio microfono", en: "Radio microphone"),
            RoomFacility(id: 142, it: "Postazioni dotate di presa elettrica",
                         en: "Seats with electric socket"),
        ]
    }

    static func mapPins() -> [MapPin] {
        [
            MapPin(id: "MIA0103", name: "Edificio 3",
                   coordinate: .init(latitude: 45.4788, longitude: 9.2272),
                   freeRooms: 7, totalRooms: 9),
            MapPin(id: "MIA0102", name: "Edificio 2",
                   coordinate: .init(latitude: 45.4781, longitude: 9.2288),
                   freeRooms: 2, totalRooms: 11),
            MapPin(id: "MIB0202", name: "Edificio B2",
                   coordinate: .init(latitude: 45.5030, longitude: 9.1560),
                   freeRooms: nil, totalRooms: 21),
        ]
    }

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
