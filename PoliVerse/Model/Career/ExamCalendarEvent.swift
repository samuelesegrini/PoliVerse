import Foundation

/// A sitting in the shape the student's calendar holds it.
///
/// Handed to the system's own event editor, so the student checks and saves it
/// themselves: the app never asks for calendar access and never reads the calendar.
nonisolated struct ExamCalendarEvent: Identifiable, Sendable, Equatable {
    /// The title and start time, which identify the sitting.
    var id: String { "\(title)@\(start.timeIntervalSince1970)" }

    /// How long a timed sitting is assumed to run.
    ///
    /// The exam services give a start time and no end. Three hours covers most written
    /// exams, and the student adjusts the rest in the editor.
    static let defaultLength: TimeInterval = 3 * 3600

    /// The teaching's name, with the sitting's type appended where there is one.
    let title: String
    /// When the sitting starts.
    let start: Date
    /// When it ends: ``defaultLength`` after ``start``, or ``start`` for an all-day
    /// entry.
    let end: Date
    /// Whether the sitting has no time of day, which the endpoint expresses as midnight
    /// in Rome.
    let isAllDay: Bool
    /// The room, once published.
    let location: String?
    /// The lecturer, the teaching code, and a line saying to check the room and time
    /// before the exam.
    let notes: String

    /// Builds a calendar entry from a sitting.
    ///
    /// - Parameter sitting: The sitting to hold.
    /// - Returns: `nil` when the sitting has no date.
    init?(sitting: ExamSession) {
        guard let date = sitting.date else { return nil }
        title = [sitting.courseName, sitting.kind?.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
        start = date
        // A date with no time arrives at midnight in Rome.
        isAllDay = PoliMiDate.romeCalendar.startOfDay(for: date) == date
        end = isAllDay ? date : date.addingTimeInterval(Self.defaultLength)
        // The same wording the timetable's own export uses, so a calendar
        // holding both reads the same way in both.
        location = sitting.room.map(RoomNaming.sentence)
        notes = [
            sitting.teacher.map { String(localized: "Docente: \($0)") },
            String(localized: "Codice: \(sitting.courseCode)"),
            // The room and the time can still change: say where to check.
            String(localized: "Da Servizi Online · verifica aula e orario prima dell'esame."),
        ].compactMap { $0 }.joined(separator: "\n")
    }

    /// Builds a calendar entry from a WeBeep assignment deadline.
    ///
    /// A deadline is a moment, not a span, so the entry is zero-length and sits
    /// at the hour Moodle gives. Moodle's usual hour is midnight, which the
    /// student reads as "by the end of the day before"; the entry still lands on
    /// the date Moodle states rather than second-guessing it.
    ///
    /// - Parameter deadline: The deadline to hold.
    init(deadline: AssignmentDeadline) {
        title = deadline.name.isEmpty ? deadline.courseName : deadline.name
        start = deadline.due
        end = deadline.due
        isAllDay = false
        location = nil
        notes = [
            String(localized: "Corso: \(deadline.courseName)"),
            String(localized: "Codice: \(deadline.courseCode)"),
            String(localized: "Da WeBeep · la consegna si fa su WeBeep."),
        ].joined(separator: "\n")
    }
}

/// Treating a blank string as absent.
private extension String {
    /// The string, or `nil` when it is empty or only whitespace.
    nonisolated var nilIfBlank: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}
