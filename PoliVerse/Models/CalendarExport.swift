import Foundation

/// The personal timetable as weekly repeating events for the iOS calendar.
nonisolated enum CalendarExport {
    struct Draft: Sendable, Equatable {
        let title: String
        let start: Date
        let end: Date
        /// The day after the last day of lessons, so a lesson on that last day
        /// is still inside the recurrence whatever time it starts.
        let repeatsUntil: Date
        let location: String?
        let notes: String?
    }

    /// One draft per visible slot with known lesson dates.
    static func drafts(for timetable: PersonalTimetable) -> [Draft] {
        let calendar = PoliMiDate.romeCalendar
        return timetable.visibleEntries.flatMap { entry -> [Draft] in
            guard let first = entry.lessonsStart, let last = entry.lessonsEnd,
                  let until = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
            else { return [] }
            return entry.slots.compactMap { slot in
                var day = calendar.startOfDay(for: first)
                while calendar.component(.weekday, from: day) != slot.weekday {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
                    day = next
                }
                guard day < until,
                      let start = calendar.date(byAdding: .minute, value: slot.startMinutes, to: day),
                      let end = calendar.date(byAdding: .minute, value: slot.endMinutes, to: day) else { return nil }
                let location = [slot.room.map { String(localized: "Aula \($0)") }, slot.address]
                    .compactMap { $0 }.joined(separator: ", ")
                return Draft(title: entry.title, start: start, end: end, repeatsUntil: until,
                             location: location.isEmpty ? nil : location,
                             notes: entry.teacher.map { String(localized: "Docente: \($0)") })
            }
        }
    }
}
