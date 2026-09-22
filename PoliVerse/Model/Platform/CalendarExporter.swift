import EventKit
import Foundation

/// Keeps the personal timetable in a calendar of its own in the Calendar app.
///
/// A separate calendar is what makes the export updatable: ``sync(_:)`` replaces it
/// whole, so a recalculated timetable moves lessons rather than duplicating them, and
/// ``remove()`` takes them all away. That requires full calendar access, because
/// write-only access cannot find what it wrote.
enum CalendarExporter {
    /// What a sync produced.
    enum Outcome: Equatable {
        /// The calendar was replaced, with how many events were written.
        case synced(Int)
        /// The student refused full calendar access.
        case denied
        /// The sync could not complete, with the reason.
        case failed(String)
    }

    /// Defaults key holding the identifier of the calendar this app created.
    private static let calendarKey = "personalTimetableCalendarID"

    /// Whether the app may sync without asking: full access is already granted and a
    /// calendar of its own already exists.
    ///
    /// This is what lets a weekly rebuild update the calendar without prompting.
    static var canSyncQuietly: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
            && UserDefaults.standard.string(forKey: calendarKey) != nil
    }

    /// Replaces the timetable's calendar with one weekly repeating event per draft.
    ///
    /// Requests full access, removes any calendar written previously, creates a fresh one
    /// on the default source, and writes every draft in a single commit. Events are
    /// stamped Europe/Rome whatever zone the device is in, since the lessons are in Milan.
    /// A failure rolls the whole commit back.
    ///
    /// - Parameter drafts: The events to write, from ``CalendarExport/drafts(for:)``.
    /// - Returns: What happened.
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

    /// Deletes the timetable's calendar and forgets its identifier.
    ///
    /// Does nothing unless ``canSyncQuietly`` holds, so it never prompts.
    static func remove() {
        guard canSyncQuietly else { return }
        let store = EKEventStore()
        removeCalendar(in: store)
        try? store.commit()
    }

    /// Removes the previously written calendar from a store without committing, and
    /// forgets its identifier.
    ///
    /// - Parameter store: The event store to remove it from.
    private static func removeCalendar(in store: EKEventStore) {
        guard let id = UserDefaults.standard.string(forKey: calendarKey) else { return }
        if let calendar = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(calendar, commit: false)
        }
        UserDefaults.standard.removeObject(forKey: calendarKey)
    }
}
