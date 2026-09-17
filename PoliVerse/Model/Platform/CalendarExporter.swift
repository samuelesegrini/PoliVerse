import EventKit
import Foundation

/// Keeps the personal timetable in its own calendar in the iOS Calendar app.
///
/// A calendar of its own, rather than events in the student's default one, is
/// what makes it updatable: syncing replaces that calendar whole, so a
/// recalculated timetable moves lessons instead of duplicating them, and
/// archiving or deleting the timetable takes them away. That needs full
/// access — write-only access cannot find what it wrote.
enum CalendarExporter {
    enum Outcome: Equatable {
        case synced(Int)
        case denied
        case failed(String)
    }

    private static let calendarKey = "personalTimetableCalendarID"

    /// Whether the app may sync without asking: the student has already said
    /// yes once, so a weekly recalculation can update the calendar quietly.
    static var canSyncQuietly: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
            && UserDefaults.standard.string(forKey: calendarKey) != nil
    }

    static func sync(_ drafts: [CalendarExport.Draft]) async -> Outcome {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents() else { return .denied }
        } catch {
            return .failed(error.localizedDescription)
        }
        do {
            removeCalendar(in: store)
            guard let source = store.defaultCalendarForNewEvents?.source
                    ?? store.sources.first(where: { $0.sourceType == .local }) else {
                return .failed(String(localized: "Nessun calendario in cui salvare."))
            }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = String(localized: "Orario personalizzato")
            calendar.source = source
            calendar.cgColor = CGColor(red: 0.13, green: 0.29, blue: 0.53, alpha: 1)
            try store.saveCalendar(calendar, commit: false)
            for draft in drafts {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = draft.title
                event.startDate = draft.start
                event.endDate = draft.end
                // Rome, whatever zone the phone is in: the lessons are in Milan.
                event.timeZone = TimeZone(identifier: "Europe/Rome")
                event.location = draft.location
                event.notes = draft.notes
                event.addRecurrenceRule(EKRecurrenceRule(
                    recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(end: draft.repeatsUntil)))
                try store.save(event, span: .futureEvents, commit: false)
            }
            try store.commit()
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
            return .synced(drafts.count)
        } catch {
            store.reset()
            return .failed(error.localizedDescription)
        }
    }

    /// Takes the timetable's calendar away, when there is one and the app may.
    static func remove() {
        guard canSyncQuietly else { return }
        let store = EKEventStore()
        removeCalendar(in: store)
        try? store.commit()
    }

    private static func removeCalendar(in store: EKEventStore) {
        guard let id = UserDefaults.standard.string(forKey: calendarKey) else { return }
        if let calendar = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(calendar, commit: false)
        }
        UserDefaults.standard.removeObject(forKey: calendarKey)
    }
}
