import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// The week is built from ``SampleDegree``'s third-year teachings, so every
/// lesson on Oggi has a course page and a sitting behind it. This ships — an
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

        // The week is the third year's first semester — the same teachings
        // the course pages and the plan carry, so a lesson on Oggi always has
        // a course behind it to open.
        func named(_ code: String) -> String { SampleDegree.teaching(code).name }

        return [
            // Monday
            event(named("095948"), 0, 8, 10, room: "Aula Rogers", acronym: "R.0.1"),
            event(named("086657"), 0, 10, 13, room: "Aula De Donato", acronym: "D.0.2"),
            // Not a lesson: office hours belong to the lecturer, not to a
            // teaching's timetable, and anything asking for the day's lessons
            // must not count them.
            event("Ricevimento — " + SampleDegree.teaching("095948").teacher, 0, 15, 16, .custom,
                  room: "Studio 3.2.7", acronym: "S.3.2"),
            // Tuesday
            event(named("095857"), 1, 9, 12, room: "Aula Castigliano", acronym: "C.1.1"),
            event(named("095948") + " — esercitazione", 1, 14, 16,
                  room: "Lab Informatico", acronym: "L.0.5"),
            // Wednesday
            event(named("086657"), 2, 8, 11, room: "Aula Rogers", acronym: "R.0.1"),
            event(named("095857"), 2, 14, 17, room: "Aula Beta", acronym: "B.1.4"),
            deadline("Consegna — " + SampleDegree.teaching("095948").assignments.first!.name, 2, 23, 59),
            // Thursday
            event(named("095948"), 3, 10, 13, room: "Aula Alfa", acronym: "A.2.3"),
            // A seminar is open to the school, not a lesson of a teaching the
            // student is enrolled in.
            event("Seminario — sistemi distribuiti in produzione", 3, 17, 19, .custom,
                  room: "Aula Rogers", acronym: "R.0.1"),
            // Friday: the lab, a mid-term, and the sitting the student is
            // enrolled in — three kinds of day in one column.
            event(named("086657") + " — laboratorio", 4, 9, 12, room: "Lab Reti", acronym: "L.1.2"),
            event("Prova in itinere — " + named("095857"), 4, 14, 16, .exam,
                  room: "Aula Magna", acronym: "M.0.1"),
            deadline("Consegna — " + SampleDegree.teaching("086657").assignments.first!.name, 4, 23, 59),
        ]
    }
}

nonisolated extension PersonalTimetable {
    /// The Manifesto's own view of the same semester: the third year's
    /// teachings, at the hours the week's lessons run.
    static var sample: PersonalTimetable { sample(now: .now) }

    static func sample(now: Date = .now) -> PersonalTimetable {
        let calendar = PoliMiDate.romeCalendar
        // The semester the student is in, not a year typed into the source.
        let year = calendar.component(.year, from: now)
            - (calendar.component(.month, from: now) >= 9 ? 0 : 1)
        let start = calendar.date(from: DateComponents(year: year, month: 9, day: 14))
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 23))
        let address = "Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 3 - Piano Primo"
        let rooms = [("3.1.4", "46"), ("3.1.1", "63"), ("5.02", "4738")]

        let entries = SampleDegree.currentTeachings.enumerated().map { index, teaching in
            let room = rooms[index % rooms.count]
            return PersonalTimetable.Entry(
                code: teaching.code,
                title: teaching.name.uppercased(),
                teacher: teaching.teacher,
                semester: teaching.semester,
                lessonsStart: start, lessonsEnd: end,
                slots: [
                    .init(weekday: 2 + index % 4, startMinutes: 495 + index * 120,
                          endMinutes: 615 + index * 120,
                          room: room.0, roomID: room.1, address: address),
                ])
        }
        return PersonalTimetable(name: "Segrini Samuele", yearCode: String(year), entries: entries,
                                 builtAt: now)
    }
}
