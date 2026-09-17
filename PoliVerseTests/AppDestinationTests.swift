import Foundation
import Testing
@testable import PoliVerse

/// Where the app can be sent from outside it: a widget tap, a Control Centre
/// button, Siri, Spotlight.
///
/// A widget tap can only carry a URL, and a Control Centre button runs in
/// another process entirely — so a destination travels either as
/// `poliverse://open/<name>` or as a value left in the shared container. Both
/// have to survive the trip exactly, and the one left behind has to be
/// consumed: a destination that stays would send the student back to the same
/// screen on every activation for the rest of the install.
@Suite("Destinazioni da fuori l’app", .serialized)
struct AppDestinationTests {
    private let all: [AppDestination] = [
        .home, .calendar, .career, .weBeep, .search, .freeRooms, .map, .plan, .simulator,
    ]

    @Test("Ogni destinazione sopravvive al giro per il suo indirizzo")
    func urlRoundTrip() {
        for destination in all {
            #expect(AppDestination(url: destination.url) == destination,
                    "\(destination.rawValue) non torna indietro dal suo indirizzo")
        }
    }

    @Test("L’indirizzo è quello dello schema dell’app")
    func urlShape() {
        #expect(AppDestination.freeRooms.url.absoluteString == "poliverse://open/freeRooms")
        #expect(AppDestination.home.url.absoluteString == "poliverse://open/home")
    }

    /// Anything else that reaches the app — another app's scheme, a link on
    /// the web, a destination from a newer release — must not be routed
    /// anywhere.
    @Test("Un indirizzo estraneo non apre niente", arguments: [
        "https://polimi.it/open/career",
        "poliverse://close/career",
        "poliverse://open/notAScreen",
        "poliverse://open",
        "poliverse://",
    ])
    func foreignURLs(raw: String) {
        guard let url = URL(string: raw) else { return }
        #expect(AppDestination(url: url) == nil, "\(raw) non doveva aprire niente")
    }

    /// The case matters: the raw values are what the widgets are built with.
    @Test("Il nome nell’indirizzo è quello grezzo, maiuscole comprese")
    func rawNameIsCaseSensitive() {
        #expect(AppDestination(url: URL(string: "poliverse://open/webeep")!) == nil)
        #expect(AppDestination(url: URL(string: "poliverse://open/weBeep")!) == .weBeep)
    }

    /// Recorded in the shared container by an intent running in another
    /// process, and read exactly once by the app.
    @Test("La destinazione lasciata da un altro processo si legge una volta sola")
    func pendingIsConsumed() {
        AppDestination.plan.send()

        #expect(AppDestination.takePending() == .plan)
        #expect(AppDestination.takePending() == nil, "La destinazione è rimasta dietro")
    }

    @Test("Senza niente in attesa non si va da nessuna parte")
    func noPending() {
        _ = AppDestination.takePending()
        #expect(AppDestination.takePending() == nil)
    }
}

/// The widget kinds the app names when it asks for a reload.
@Suite("Tipi di widget")
struct WidgetKindTests {
    /// The strings are the ones the extension declares; changing one silently
    /// makes the app reload a widget that does not exist.
    @Test("I nomi sono quelli dichiarati dall’estensione")
    func names() {
        #expect(WidgetKind.today.rawValue == "Today")
        #expect(WidgetKind.nextLecture.rawValue == "NextLecture")
        #expect(WidgetKind.career.rawValue == "Career")
        #expect(WidgetKind.freeRooms.rawValue == "FreeRooms")
    }

    /// Aule libere fetches on its own; the other three read the agenda file,
    /// so a new agenda is exactly what they need to be told about.
    @Test("Chi legge l’agenda è detto, e le aule libere non ci sono")
    func agendaReaders() {
        #expect(WidgetKind.agenda == [.today, .nextLecture, .career])
        #expect(!WidgetKind.agenda.contains(.freeRooms))
        #expect(WidgetKind.agenda.isSubset(of: Set(WidgetKind.allCases)))
    }
}
