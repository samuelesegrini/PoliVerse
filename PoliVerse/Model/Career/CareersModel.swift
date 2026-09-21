import Foundation
import Observation
import OSLog

/// The enrolments this person has, and which one the app is using.
///
/// The matricola is not a display detail: nearly every PoliMi endpoint is
/// parameterised by it, and the OAuth token is bound to one enrolment. Point
/// the app at a closed career and `iae` answers "Utente non abilitato Code: 6"
/// for everything — which is exactly how this was found.
@Observable
final class CareersModel {
    private(set) var careers: [Career] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Only who is signed in and the transport — see ``Account``.
    private let account: any Account
    /// Where the per-person choice is kept. Injectable so a test cannot see
    /// another's, which `UserDefaults.standard` made unavoidable.
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "careers")

    /// The matricola the user last chose, per person. Keyed by `codicePersona`
    /// so two accounts on one device cannot inherit each other's choice.
    private func storedChoice(for personCode: String) -> String? {
        defaults.string(forKey: "career-\(personCode)")
    }

    private func store(_ matricola: String, for personCode: String) {
        defaults.set(matricola, forKey: "career-\(personCode)")
    }

    var current: Career? {
        careers.first { $0.matricola == account.matricola }
    }

    /// Whether a switcher is worth showing at all.
    var hasChoice: Bool { careers.count > 1 }

    init(account: any Account, defaults: UserDefaults = .standard) {
        self.account = account
        self.defaults = defaults
    }

    func load() async {
        guard !isLoading, careers.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if account.isSample {
            careers = Career.samples()
            return
        }

        do {
            let data = try await account.http.data(
                for: APIRequest(host: .app, path: "/v1/careers/list"))
            // Parses the payload a second time, on the main actor: a question
            // for a debugger, not a cost every student should pay.
            #if DEBUG
            log.notice("careers payload shape: \(JSONShape.describe(data), privacy: .public)")
            #endif
            careers = try await BackgroundJSON.decode(CareersResponse.self, from: data).careers
            log.notice("careers: \(self.careers.count, privacy: .public) — \(self.careers.map { "\($0.matricola) \($0.status ?? "?")" }.joined(separator: ", "), privacy: .public)")
        } catch {
            log.error("Careers list failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
        }
    }

    /// The career the app should be on, if it is not already.
    ///
    /// Returns nil when the current matricola is fine. Deliberately advisory:
    /// switching re-runs OAuth and takes the user through a web view, so it is
    /// offered rather than done behind their back.
    func suggestedSwitch() -> Career? {
        guard let personCode = account.personCode, careers.count > 1 else { return nil }
        let wanted = storedChoice(for: personCode).flatMap { stored in
            careers.first { $0.matricola == stored }
        } ?? Career.preferred(in: careers)
        guard let wanted, wanted.matricola != account.matricola else { return nil }
        return wanted
    }

    /// Remembers the choice, so the app does not offer the same switch again.
    func remember(_ career: Career) {
        guard let personCode = account.personCode else { return }
        store(career.matricola, for: personCode)
    }

    /// Tells the Politecnico which enrolment to default to next time.
    ///
    /// `PUT /v1/careers/favorite/{matricola}` — the official app sends it
    /// alongside the switch. Best effort: the local choice is what this app
    /// acts on, and a failure here changes nothing the user can see.
    func markFavourite(_ career: Career) async {
        do {
            _ = try await account.http.data(for: APIRequest(
                host: .app,
                path: "/v1/careers/favorite/\(career.matricola)",
                method: "PUT"))
            log.notice("favourite career set to \(career.matricola, privacy: .public)")
        } catch {
            log.error("Could not set favourite career: \(error.localizedDescription)")
        }
    }
}
