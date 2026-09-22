import Foundation

/// The one place the widgets read the student's cached agenda.
///
/// An extension has no session and no network of its own: everything it shows
/// was written by the app into the shared container. Keeping the read here
/// means every widget agrees on *whose* records those are and how stale they
/// are allowed to look.
enum WidgetAgenda {
    /// The app group's offline store, where the app writes the agenda.
    private static var store: OfflineStore {
        OfflineStore(groupIdentifier: OfflineStore.groupIdentifier)
    }

    /// Whether anyone is signed in. Distinct from an empty agenda: "accedi"
    /// and "niente in programma" are different answers and a widget that shows
    /// the second when it means the first is simply wrong.
    static var isSignedIn: Bool { SharedAccount.matricola != nil }

    /// The cached events and the age of the cache, or `nil` when signed out.
    static func load() -> (events: [AgendaEvent], age: TimeInterval)? {
        guard let matricola = SharedAccount.matricola,
              let slot = store.load([AgendaEvent].self, as: "agenda", account: matricola)
        else { return nil }
        return (slot.value, slot.age)
    }

    /// Events overlapping the calendar day containing `date`, in order.
    ///
    /// Overlapping rather than starting: a lecture that began before midnight
    /// of a long day, or one already under way when the widget is drawn, still
    /// belongs to the day being shown.
    static func events(on date: Date, from all: [AgendaEvent]) -> [AgendaEvent] {
        let calendar = Calendar.current
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        return all
            .filter { $0.start < day.end && $0.end >= day.start }
            .sorted { $0.start < $1.start }
    }
}
