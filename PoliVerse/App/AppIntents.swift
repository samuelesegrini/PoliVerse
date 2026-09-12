import AppIntents
import SwiftUI

/// What the app can be asked to do from outside it: Siri, Spotlight's action
/// row, and the Shortcuts app.
///
/// Each intent only opens a screen. Nothing here reads or writes university
/// data on its own — an intent runs without the app in front of the user, and
/// a "check my exams" that quietly authenticated in the background is not
/// something to build casually.
nonisolated enum AppDestination: String, Sendable {
    case home, calendar, career, weBeep, search, freeRooms, map, plan, simulator

    /// Deep links arrive here from every direction — intents, Spotlight,
    /// Handoff — so the routing lives in one place.
    static let notification = Notification.Name("one.wape.PoliVerse.navigate")

    func send() {
        NotificationCenter.default.post(name: Self.notification, object: rawValue)
    }
}

struct OpenTimetableIntent: AppIntent {
    static let title: LocalizedStringResource = "Apri l'orario"
    static let description = IntentDescription("Mostra le lezioni di oggi.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDestination.calendar.send()
        return .result()
    }
}

struct OpenFreeRoomsIntent: AppIntent {
    static let title: LocalizedStringResource = "Trova un'aula libera"
    static let description = IntentDescription("Mostra le aule libere adesso.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDestination.freeRooms.send()
        return .result()
    }
}

struct OpenCareerIntent: AppIntent {
    static let title: LocalizedStringResource = "Apri la carriera"
    static let description = IntentDescription("Media, CFU ed esami sostenuti.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDestination.career.send()
        return .result()
    }
}

struct OpenMaterialsIntent: AppIntent {
    static let title: LocalizedStringResource = "Apri WeBeep"
    static let description = IntentDescription("I materiali dei tuoi corsi.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDestination.weBeep.send()
        return .result()
    }
}

/// The phrases Siri accepts. Each needs `.applicationName` somewhere in it,
/// so they read as "… in PoliVerse" rather than competing with every other
/// app's "apri l'orario".
struct PoliVerseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTimetableIntent(),
            phrases: ["Apri l'orario in \(.applicationName)",
                      "Lezioni di oggi in \(.applicationName)"],
            shortTitle: "Orario",
            systemImageName: "calendar")
        AppShortcut(
            intent: OpenFreeRoomsIntent(),
            phrases: ["Trova un'aula libera in \(.applicationName)",
                      "Aule libere in \(.applicationName)"],
            shortTitle: "Aule libere",
            systemImageName: "building.2")
        AppShortcut(
            intent: OpenCareerIntent(),
            phrases: ["Apri la carriera in \(.applicationName)",
                      "La mia media in \(.applicationName)"],
            shortTitle: "Carriera",
            systemImageName: "chart.bar")
        AppShortcut(
            intent: OpenMaterialsIntent(),
            phrases: ["Apri WeBeep in \(.applicationName)",
                      "Materiali dei corsi in \(.applicationName)"],
            shortTitle: "WeBeep",
            systemImageName: "books.vertical")
    }
}
