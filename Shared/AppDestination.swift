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
        // Two channels, because the same intent can run in two processes.
        //
        // Tapping a Control Center button runs `perform()` in the *extension*,
        // where a NotificationCenter post reaches nobody: the app is a
        // separate process and may not even be running. Recording the
        // destination in the shared container lets the app pick it up the
        // moment it comes forward. When `perform()` does run in the app, the
        // notification arrives first and the pending value is consumed as a
        // no-op.
        SharedAccount.defaults.set(rawValue, forKey: Self.pendingKey)
        NotificationCenter.default.post(name: Self.notification, object: rawValue)
    }

    private static let pendingKey = "pendingDestination"

    /// The destination an out-of-process intent asked for, read once.
    ///
    /// Consuming rather than peeking: a destination left behind would send the
    /// user back to the same screen on every activation for the rest of the
    /// install.
    static func takePending() -> AppDestination? {
        let defaults = SharedAccount.defaults
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return AppDestination(rawValue: raw)
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

