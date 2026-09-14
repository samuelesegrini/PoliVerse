import EventKit
import EventKitUI
import SwiftUI

/// The system's event editor, pre-filled with a sitting.
///
/// The editor runs outside the app: saving from it needs no calendar
/// permission, and PoliVerse never sees the student's calendar.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let event: ExamCalendarEvent
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let draft = EKEvent(eventStore: store)
        draft.title = event.title
        draft.startDate = event.start
        draft.endDate = event.end
        draft.isAllDay = event.isAllDay
        draft.location = event.location
        draft.notes = event.notes
        // Rome, whatever zone the phone is in: the exam is in Milan. Not for
        // an all-day event, which EventKit keeps floating on its date.
        if !event.isAllDay { draft.timeZone = TimeZone(identifier: "Europe/Rome") }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = draft
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            done()
        }
    }
}
