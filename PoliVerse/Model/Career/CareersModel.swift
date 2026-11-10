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
    /// The list, through the shared loader: a second caller joins the load in
    /// flight, and the list is read once a day at most.
    private let query: Query<CareersSource>

    /// The enrolments, once loaded.
    var careers: [Career] { query.value ?? [] }
    /// `true` while the list is loading.
    var isLoading: Bool { query.isLoading }
    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? { query.errorMessage }

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
        self.query = Query(CareersSource(), account: account)
    }

    /// Loads the list, once a day at most; a call while it loads joins it.
    func load() async {
        await query.load()
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
            log.notice("favourite career set to \(career.matricola, privacy: .private(mask: .hash))")
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

/// The student's enrolments, from `/v1/careers/list`.
///
/// Kept in memory only, as before: the list is the first thing read after
/// signing in, and a stale copy would offer a switch to a career that closed.
nonisolated struct CareersSource: Resource {
    static let id = "careers"
    /// A day: enrolments change once a year, and the list used to be read once a launch.
    static let ttl: TimeInterval = 86_400
    static let persistence: Persistence = .memory

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "careers")

    @concurrent
    func fetch(_ key: Whole, env: Env, previous: [Career]?) async throws -> [Career] {
        let data = try await env.http.data(for: APIRequest(host: .app, path: "/v1/careers/list"))
        #if DEBUG
        Self.log.notice("careers payload shape: \(JSONShape.describe(data), privacy: .public)")
        #endif
        let careers = try await BackgroundJSON.decode(CareersResponse.self, from: data).careers
        Self.log.notice("careers: \(careers.count, privacy: .public) — \(careers.map { "\($0.matricola) \($0.status ?? "?")" }.joined(separator: ", "), privacy: .private(mask: .hash))")
        return careers
    }

    func sample(_ key: Whole) -> [Career]? { Career.samples() }
}
