import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension AgendaEvent {
    static func samples(around date: Date) -> [AgendaEvent] {
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
            event(Course.geometry.name, 0, 8, 10, room: "Aula Rogers", acronym: "R.0.1"),
            event("Architetture dei Calcolatori", 0, 10, 13, room: "Aula De Donato", acronym: "D.0.2"),
            event(Course.databases.name, 1, 9, 12, room: "Aula Castigliano", acronym: "C.1.1"),
            event(Course.logicNetworks.name, 1, 14, 16, room: "Aula Alfa", acronym: "A.2.3"),
            event(Course.control.name, 2, 8, 11, room: "Aula Rogers", acronym: "R.0.1"),
            event(Course.softwareEngineering.name, 2, 14, 17, room: "Aula Beta", acronym: "B.1.4"),
            deadline("Consegna progetto IS", 2, 23, 59),
            event("Basi di Dati — esercitazione", 3, 10, 13, room: "Lab Informatico", acronym: "L.0.5"),
            event("Architetture dei Calcolatori", 4, 9, 12, room: "Aula De Donato", acronym: "D.0.2"),
            event("Prova in itinere — Analisi 2", 4, 14, 16, .exam, room: "Aula Magna", acronym: "M.0.1"),
        ]
    }
}

nonisolated extension PersonalTimetable {
    static var sample: PersonalTimetable {
        let calendar = PoliMiDate.romeCalendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 23))
        let address = "Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 3 - Piano Primo"
        return PersonalTimetable(name: "Rossi Mario", yearCode: "2026", entries: [
            .init(code: "052496", title: "ALGORITHMS AND PARALLEL COMPUTING", teacher: "Rossi Matteo Giovanni",
                  semester: 1, lessonsStart: start, lessonsEnd: end, slots: [
                    .init(weekday: 2, startMinutes: 495, endMinutes: 615, room: "3.1.4", roomID: "46", address: address),
                    .init(weekday: 4, startMinutes: 615, endMinutes: 735, room: "3.1.1", roomID: "63", address: address),
                  ]),
            .init(code: "059156", title: "ANALISI MATEMATICA 1 E GEOMETRIA", teacher: "Notari Roberto",
                  semester: 1, lessonsStart: start, lessonsEnd: end, slots: [
                    .init(weekday: 2, startMinutes: 495, endMinutes: 615, room: "5.02", roomID: "4738", address: address),
                  ]),
        ], builtAt: .now)
    }
}
