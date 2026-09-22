import Foundation

/// Turns a personal timetable into weekly repeating events for the system calendar.
///
/// The drafts are handed to the system's own event editor, so the student reviews and
/// saves them; the app never asks for calendar access.
nonisolated enum CalendarExport {
    /// One weekly repeating event, ready for the event editor.
    struct Draft: Sendable, Equatable {
        /// The teaching's name.
        let title: String
        /// The first occurrence's start.
        let start: Date
        /// The first occurrence's end.
        let end: Date
        /// The day after the last day of lessons, so a lesson on that last day is still inside
        /// the recurrence whatever time it starts.
        let repeatsUntil: Date
        /// The room and the address, where either is known.
        let location: String?
        /// The lecturer, where one is known.
        let notes: String?
    }

    /// One draft per visible slot with known lesson dates.
    ///
    /// The first occurrence is the slot's weekday on or after the first day of lessons.
    /// Teachings without both lesson dates, and slots whose first occurrence falls past
    /// the last day, are skipped.
    ///
    /// - Parameter timetable: The timetable to export.
    /// - Returns: The drafts.
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
                let location = [slot.room.map(RoomNaming.sentence), slot.address]
                    .compactMap { $0 }.joined(separator: ", ")
                return Draft(title: entry.title, start: start, end: end, repeatsUntil: until,
                             location: location.isEmpty ? nil : location,
                             notes: entry.teacher.map { String(localized: "Docente: \($0)") })
            }
        }
    }
}
