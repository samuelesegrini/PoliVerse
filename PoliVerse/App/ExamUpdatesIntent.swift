import AppIntents
import Foundation

/// "Novità sui miei esami" — answered by Siri without opening the app.
///
/// Read from the feed's log on disk: it says what the app last noticed and
/// does not fetch, which is the honest answer from a lock screen. Asks for
/// the phone to be unlocked first: news about someone's exams is theirs.
struct ExamUpdatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Novità sui miei esami"
    static let description = IntentDescription("Esiti, aule e annunci della settimana, secondo l'ultimo aggiornamento dell'app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

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
    static let title: LocalizedStringResource = "Prossimo esame"
    static let description = IntentDescription("Il prossimo appello in programma, secondo l'ultimo aggiornamento dell'app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

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
