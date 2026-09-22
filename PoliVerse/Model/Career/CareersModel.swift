import Foundation
import Observation
import OSLog

/// The enrolments this person has, and which one the app is using.
///
/// The matricola is not a display detail: nearly every endpoint is parameterised by
/// it and the OAuth token is bound to one enrolment, so pointing the app at a closed
/// career has the exam services refuse everything.
///
/// ``suggestedSwitch()`` is advisory — switching re-runs the OAuth flow and takes the
/// student through a web view, so it is offered rather than performed.
@Observable
final class CareersModel {
    /// The enrolments, once loaded.
    private(set) var careers: [Career] = []
    /// `true` while the list is loading.
    private(set) var isLoading = false
    /// The last load's error, or `nil` when it succeeded.
    private(set) var errorMessage: String?

    /// Who is signed in, and the transport.
    private let account: any Account
    /// Where the per-person choice is kept. Injected so that two tests in one run cannot
    /// see each other's.
    private let defaults: UserDefaults
    /// Diagnostic log for this type, under the `careers` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "careers")

    /// The matricola this person last chose.
    ///
    /// Keyed by person code, so two accounts on one device cannot inherit each other's
    /// choice.
    ///
    /// - Parameter personCode: Whose choice to read.
    /// - Returns: The matricola, or `nil` when they have not chosen.
    private func storedChoice(for personCode: String) -> String? {
        defaults.string(forKey: "career-\(personCode)")
    }

    /// Records this person's choice.
    ///
    /// - Parameters:
    ///   - matricola: The enrolment they chose.
    ///   - personCode: Whose choice it is.
    private func store(_ matricola: String, for personCode: String) {
        defaults.set(matricola, forKey: "career-\(personCode)")
    }

    /// The enrolment the token is bound to, or `nil` when it is not in the list.
    var current: Career? {
        careers.first { $0.matricola == account.matricola }
    }

    /// Whether a switcher is worth showing at all.
    var hasChoice: Bool { careers.count > 1 }

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - account: Who is signed in.
    ///   - defaults: Where the per-person choice is kept.
    init(account: any Account, defaults: UserDefaults = .standard) {
        self.account = account
        self.defaults = defaults
    }

    /// Loads the enrolment list once.
    ///
    /// Returns immediately when a load is in flight or the list is already held. A sample
    /// account gets ``Career/samples()``. A failure leaves the list empty and sets
    /// ``errorMessage``.
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

    /// The enrolment the app should be on, if it is not already.
    ///
    /// The student's remembered choice wins, falling back to ``Career/preferred(in:)``.
    ///
    /// - Returns: The enrolment to offer, or `nil` when the current matricola is already
    ///   right or there is nothing to choose between.
    func suggestedSwitch() -> Career? {
        guard let personCode = account.personCode, careers.count > 1 else { return nil }
        let wanted = storedChoice(for: personCode).flatMap { stored in
            careers.first { $0.matricola == stored }
        } ?? Career.preferred(in: careers)
        guard let wanted, wanted.matricola != account.matricola else { return nil }
        return wanted
    }

    /// Records the student's choice, so the same switch is not offered again.
    ///
    /// - Parameter career: The enrolment they chose.
    func remember(_ career: Career) {
        guard let personCode = account.personCode else { return }
        store(career.matricola, for: personCode)
    }

    /// Tells the Politecnico which enrolment to bind the next token to.
    ///
    /// This is the lever that actually decides the enrolment a fresh sign-in lands on.
    /// Best effort: a failure is logged and changes nothing the student can see.
    ///
    /// - Parameter career: The enrolment to favour.
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
/// ``CareersModel`` satisfies ``Enrolments``, with the matricole projected out.
///
/// Declared here rather than beside the protocol, for the reason given on
/// ``CareerModel``'s own conformance: a `Sendable` conformance stated in
/// another file is retroactive.
extension CareersModel: Enrolments {
    /// The matricole of every known enrolment.
    var matricole: [String] { careers.map(\.matricola) }
}
