import AppIntents
import Foundation

/// "Novità sui miei esami" — answered by Siri without opening the app.
///
/// Read from the feed's log on disk: it says what the app last noticed and
/// does not fetch, which is the honest answer from a lock screen. Asks for
/// the phone to be unlocked first: news about someone's exams is theirs.
struct ExamUpdatesIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Novità sui miei esami"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Esiti, aule e annunci della settimana, secondo l'ultimo aggiornamento dell'app.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = false
    /// Requires an unlocked device: the answer names the student's own exams.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// Answers with the week's exam news, read from what the app has already recorded.
    ///
    /// - Returns: A spoken dialogue from ``ExamUpdatesSummary/spoken(_:now:)``.
    /// - Throws: Nothing in practice; an unreadable log answers that there is no news.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let matricola = SharedAccount.matricola else {
            return .result(dialog: "Accedi a PoliVerse per vedere le novità sui tuoi esami.")
        }
        // No log yet is not "signed out": it is simply no news.
        let updates = OfflineStore.shared
            .load(ExamUpdateLog.self, as: ExamUpdateLog.name, account: matricola)?.value.updates ?? []
        return .result(dialog: IntentDialog(stringLiteral: ExamUpdatesSummary.spoken(updates, now: .now)))
    }
}

/// "Quando è il prossimo esame?" — from the same snapshot the career widget
/// reads.
struct NextExamIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Prossimo esame"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Il prossimo appello in programma, secondo l'ultimo aggiornamento dell'app.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = false
    /// Requires an unlocked device: the answer names the student's own next exam.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// Answers with the next exam sitting, read from the widgets' snapshot.
    ///
    /// - Returns: A spoken dialogue from ``NextExamSummary/spoken(_:now:locale:)``.
    /// - Throws: Nothing in practice; a missing snapshot answers that none is scheduled.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let matricola = SharedAccount.matricola else {
            return .result(dialog: "Accedi a PoliVerse per vedere i tuoi appelli.")
        }
        let snapshot = OfflineStore.shared
            .load(CareerSnapshot.self, as: CareerSnapshot.cacheName, account: matricola)?.value
        return .result(dialog: IntentDialog(stringLiteral: NextExamSummary.spoken(snapshot, now: .now)))
    }
}
