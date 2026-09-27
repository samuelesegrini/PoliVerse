import EventKit
#if os(iOS)
import EventKitUI
#endif
import SwiftUI

#if os(iOS)

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
#else
/// The Mac's version: EventKitUI's editor is iPhone and iPad only, so the sitting is
/// shown for confirmation and saved to the default calendar with write-only access.
///
/// Write-only access lets PoliVerse add the event without ever reading the student's
/// calendar, the same promise the iPhone editor keeps.
struct AddToCalendarSheet: View {
    /// The sitting to add.
    let event: ExamCalendarEvent
    /// Closes this sheet.
    @Environment(\.dismiss) private var dismiss
    /// Why saving failed, when it did.
    @State private var failure: String?
    /// Whether a save is in flight.
    @State private var saving = false

    /// The confirmation form.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Aggiungi a Calendario", systemImage: "calendar.badge.plus")
                .font(.headline)
            Form {
                LabeledContent("Evento", value: event.title)
                LabeledContent("Quando") {
                    if event.isAllDay {
                        Text(event.start, format: .dateTime.day().month(.wide).year())
                    } else {
                        Text(event.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    }
                }
                if let location = event.location, !location.isEmpty {
                    LabeledContent("Dove", value: location)
                }
            }
            .formStyle(.columns)
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Aggiungi") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// Asks for write-only access and saves the event to the default calendar.
    private func save() async {
        saving = true
        defer { saving = false }
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                failure = String(localized: "PoliVerse non può scrivere nel Calendario. Consentilo in Impostazioni di Sistema › Privacy e sicurezza › Calendari.")
                return
            }
            let draft = EKEvent(eventStore: store)
            draft.title = event.title
            draft.startDate = event.start
            draft.endDate = event.end
            draft.isAllDay = event.isAllDay
            draft.location = event.location
            draft.notes = event.notes
            // Rome, whatever zone the Mac is in: the exam is in Milan.
            if !event.isAllDay { draft.timeZone = TimeZone(identifier: "Europe/Rome") }
            draft.calendar = store.defaultCalendarForNewEvents
            try store.save(draft, span: .thisEvent)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
#endif
