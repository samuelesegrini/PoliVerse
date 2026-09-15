import Foundation

/// The lesson to show above the tab bar: the one in progress, or else the
/// next one still to start today.
nonisolated struct CurrentClass: Equatable, Sendable {
    let event: AgendaEvent
    let isOngoing: Bool

    /// Share of the lesson already gone, 0…1; 0 before it starts.
    func progress(at now: Date) -> Double {
        let length = event.end.timeIntervalSince(event.start)
        guard isOngoing, length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(event.start) / length, 0), 1)
    }

    /// Lectures and exams only: a deadline is a moment, not a class.
    static func pick(from events: [AgendaEvent], now: Date, calendar: Calendar = PoliMiDate.romeCalendar) -> CurrentClass? {
        let today = events
            .filter { [.lecture, .exam].contains($0.kind) && calendar.isDate($0.start, inSameDayAs: now) && $0.end > now }
            .sorted { $0.start < $1.start }
        if let ongoing = today.first(where: { $0.isOngoing(at: now) }) {
            return CurrentClass(event: ongoing, isOngoing: true)
        }
        return today.first.map { CurrentClass(event: $0, isOngoing: false) }
    }
}
