import EventKit
import Foundation

/// Writes the personal timetable into the iOS calendar.
///
/// Write-only access: PoliVerse adds the lessons but never reads the
/// student's calendar. Because it cannot read, it cannot find what it added
/// before either, so a second export adds a second copy — the screen says so.
enum CalendarExporter {
    enum Outcome: Equatable {
        case added(Int)
        case denied
        case failed(String)
    }

    static func export(_ drafts: [CalendarExport.Draft]) async -> Outcome {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return .denied }
        } catch {
            return .failed(error.localizedDescription)
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return .failed(String(localized: "Nessun calendario in cui salvare."))
        }
        do {
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
            return .added(drafts.count)
        } catch {
            store.reset()
            return .failed(error.localizedDescription)
        }
    }
}
