import Foundation

/// A sitting, as the student's calendar should hold it.
///
/// Built here and handed to the system's own event editor, which lets the
/// student check and save it: the app never asks for access to the calendar
/// and never reads it.
nonisolated struct ExamCalendarEvent: Identifiable, Sendable, Equatable {
    var id: String { "\(title)@\(start.timeIntervalSince1970)" }

    /// The exam services give a start time, not an end. Three hours covers
    /// most written exams; the student adjusts the rest in the editor.
    static let defaultLength: TimeInterval = 3 * 3600

    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String

    init?(sitting: ExamSession) {
        guard let date = sitting.date else { return nil }
        title = [sitting.courseName, sitting.kind?.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
        start = date
        // A date with no time arrives at midnight in Rome.
        isAllDay = PoliMiDate.romeCalendar.startOfDay(for: date) == date
        end = isAllDay ? date : date.addingTimeInterval(Self.defaultLength)
        location = sitting.room
        notes = [
            sitting.teacher.map { String(localized: "Docente: \($0)") },
            String(localized: "Codice: \(sitting.courseCode)"),
            // The room and the time can still change: say where to check.
            String(localized: "Da Servizi Online · verifica aula e orario prima dell'esame."),
        ].compactMap { $0 }.joined(separator: "\n")
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}
