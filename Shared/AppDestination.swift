import AppIntents
import SwiftUI

/// A screen the app can be asked to open from outside it — by Siri, by Spotlight's
/// action row, by the Shortcuts app or by a widget tap.
///
/// Every intent in this file only opens a screen; none reads or writes university
/// data, since an intent runs without the app in front of the student. The two
/// intents that do answer a question, ``ExamUpdatesIntent`` and ``NextExamIntent``,
/// read only what the app has already cached and require an unlocked device.
///
/// A destination travels by two channels — see ``send()`` — and the app collects
/// it through ``AppShellDuties``.
nonisolated enum AppDestination: String, Sendable {
    /// The routable screens: Oggi, the calendar, the career, WeBeep materials, search,
    /// free rooms, the campus map, the study plan and the grade simulator.
    case home, calendar, career, weBeep, search, freeRooms, map, plan, simulator

    /// Carries a destination's raw value in its `object`.
    ///
    /// Deep links from every direction — intents, Spotlight, widgets — are posted
    /// here, so the routing exists once.
    static let notification = Notification.Name("segrini.samuele.PoliVerse.navigate")

    /// Asks the app to open this destination, by both available channels.
    ///
    /// An intent invoked from Control Center runs in the widget extension, where a
    /// notification reaches nobody: the destination is recorded in the shared
    /// container and collected by ``takePending()`` when the app next comes forward.
    /// When the intent does run inside the app, the notification arrives first and
    /// the recorded value is consumed as a no-op.
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

    /// The `poliverse://open/<destination>` link for this destination.
    ///
    /// A widget tap can only open a URL, not run an intent that routes, so widget
    /// destinations travel through the app's own scheme into the same routing as
    /// everything else.
    var url: URL { URL(string: "poliverse://open/\(rawValue)")! }

    /// Parses a `poliverse://open/<destination>` link.
    ///
    /// - Parameter url: The link to parse.
    /// - Returns: `nil` unless the scheme is `poliverse`, the host is `open`, and the
    ///   last path component names a destination.
    init?(url: URL) {
        guard url.scheme == "poliverse", url.host == "open",
              let destination = AppDestination(rawValue: url.lastPathComponent)
        else { return nil }
        self = destination
    }

    /// Shared-defaults key holding the destination an out-of-process intent asked for.
    private static let pendingKey = "pendingDestination"

    /// Reads and clears the destination an out-of-process intent asked for.
    ///
    /// Consuming rather than peeking: a destination left in place would send the
    /// student back to the same screen on every activation.
    ///
    /// - Returns: The pending destination, or `nil` when there is none.
    static func takePending() -> AppDestination? {
        let defaults = SharedAccount.defaults
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return AppDestination(rawValue: raw)
    }
}

/// Opens the app on the calendar. Exposed to Siri and Shortcuts as “Apri
/// l'orario”.
struct OpenTimetableIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Apri l'orario"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Mostra le lezioni di oggi.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = true

    @MainActor
    /// Runs the intent.
    ///
    /// - Returns: An empty result; the intent's effect is the navigation it performs.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult {
        AppDestination.calendar.send()
        return .result()
    }
}

/// Opens the app on free rooms. Exposed to Siri and Shortcuts as “Trova un'aula
/// libera”.
struct OpenFreeRoomsIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Trova un'aula libera"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Mostra le aule libere adesso.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = true

    @MainActor
    /// Runs the intent.
    ///
    /// - Returns: An empty result; the intent's effect is the navigation it performs.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult {
        AppDestination.freeRooms.send()
        return .result()
    }
}

/// Opens the app on the career. Exposed to Siri and Shortcuts as “Apri la
/// carriera”.
struct OpenCareerIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Apri la carriera"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Media, CFU ed esami sostenuti.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = true

    @MainActor
    /// Runs the intent.
    ///
    /// - Returns: An empty result; the intent's effect is the navigation it performs.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult {
        AppDestination.career.send()
        return .result()
    }
}

/// Opens the app on WeBeep materials. Exposed to Siri and Shortcuts as “Apri
/// WeBeep”.
struct OpenMaterialsIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Apri WeBeep"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("I materiali dei tuoi corsi.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = true

    @MainActor
    /// Runs the intent.
    ///
    /// - Returns: An empty result; the intent's effect is the navigation it performs.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult {
        AppDestination.weBeep.send()
        return .result()
    }
}

