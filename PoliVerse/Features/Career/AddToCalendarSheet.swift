import EventKit
import EventKitUI
import SwiftUI

/// The system's event editor, pre-filled with a sitting.
///
/// The editor runs outside the app: saving from it needs no calendar
/// permission, and PoliVerse never sees the student's calendar.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    /// The sitting the editor opens pre-filled with.
    let event: ExamCalendarEvent
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss

    /// Builds the editor with a draft event made from the sitting.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The editor.
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

    /// Nothing to update: the draft is fixed once the editor is open.
    ///
    /// - Parameters:
    ///   - controller: The editor.
    ///   - context: The representable's context.
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// Creates the delegate that closes the sheet when the editor finishes.
    ///
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    /// Closes the sheet once the editor is done, whether the event was saved or not.
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        /// Closes the sheet.
        let done: () -> Void
        /// Creates the coordinator.
        ///
        /// - Parameter done: What to call when the editor finishes.
        init(done: @escaping () -> Void) { self.done = done }

        /// Closes the sheet.
        ///
        /// - Parameters:
        ///   - controller: The editor.
        ///   - action: What the student did with it.
        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            done()
        }
    }
}
