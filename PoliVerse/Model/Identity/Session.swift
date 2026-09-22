import Foundation
import UserNotifications
import Observation
import OSLog

/// Whether the app has a usable Politecnico session, who it belongs to, and the
/// transport everything else talks through.
///
/// The composition root for identity: it owns the ``TokenStore``, the
/// ``ServiceDirectory``, the ``PoliMiAPI`` built over them, and the ``LoginFlow``
/// that moves it between states. It conforms to ``Account``, which is how every
/// ``Store`` learns whose data it is loading.
///
/// ``state`` is changed only from within this type and from ``LoginFlow``, through
/// ``enter(_:)``.
///
/// Nothing here touches the network at init: the Keychain is read on first use and
/// ``ServiceDirectory/load()`` is driven by ``LoginFlow/restore()``.
@Observable
final class Session {
    /// Where the session stands.
    enum State: Equatable {
        /// Before ``LoginFlow/restore()`` has decided anything.
        case loading
        /// No usable token. The sign-in screen is shown.
        case signedOut
        /// An authorisation code is being exchanged for a token pair.
        case exchangingCode
        /// Signed in, with the student the token belongs to.
        case signedIn(Student)
        /// Sign-in did not complete, with a sentence explaining why.
        case failed(String)
    }

    /// Where the session stands. Moved only by this type and by ``LoginFlow``, through
    /// ``enter(_:)``.
    internal private(set) var state: State = .loading

    /// Whether every screen renders representative data instead of this student's.
    ///
    /// Off by default, persisted in `UserDefaults`, and offered explicitly during the
    /// first run by ``WelcomeStepView``. ``Account/isSample`` mirrors it, which is how
    /// it reaches every ``Store``.
    var useMockData: Bool {
        didSet { UserDefaults.standard.set(useMockData, forKey: "useMockData") }
    }

    /// The token pair, and the single refresh in flight.
    let tokens: TokenStore
    /// Where each backend lives, and the OAuth configuration.
    let directory = ServiceDirectory()
    /// The authenticated transport. Built in ``init()`` and non-nil thereafter.
    private(set) var api: PoliMiAPI!

    /// The value sent as `poliAuthProfile`. Starts at the student profile and is
    /// refined by ``loadProfile()``.
    private(set) var profileID: Int = PoliMiProfile.default

    /// `true` when the Politecnico accepted the sign-in but refuses the token for its
    /// data services.
    ///
    /// Kept apart from ``state`` because the two differ: the session is good, a subset
    /// of services is not. Set by the transport's scope-refusal callback and cleared by
    /// a fresh sign-in.
    var serviceAuthorizationFailed = false
    /// Diagnostic log for this type, under the `session` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "session")
    /// Carries the profile id and matricola to the transport, which is not main-actor
    /// bound. Built in ``init()`` and non-nil thereafter.
    var profileBox: ProfileBox!

    /// How the student signs in. Owned here so that the order in which the session and
    /// the sign-in are built cannot come apart.
    private(set) var login: LoginFlow!

    /// Builds the token store, the transport and the sign-in flow.
    ///
    /// The refresh call is supplied as a closure over an ephemeral session and the
    /// fallback base URL, rather than reaching back into ``PoliMiAPI``: refresh has to
    /// work before anything else has loaded, and routing it through the transport would
    /// let a refresh recurse into itself on a 401. It carries a 20-second timeout,
    /// since every other request waits behind it.
    ///
    /// A scope refusal sets ``serviceAuthorizationFailed`` rather than signing the
    /// student out. The token is genuinely valid — the identity endpoints accept it —
    /// so signing out would only send them round the sign-in again to the same result.
    init() {
        self.useMockData = UserDefaults.standard.object(forKey: "useMockData") as? Bool ?? false

        // The refresh closure is injected rather than reaching back into the
        // API client, which would be a retain cycle and would let a refresh
        // recurse into itself on a 401.
        let refreshSession = URLSession(configuration: .ephemeral)
        self.tokens = TokenStore(storage: KeychainTokenPersistence()) { refreshToken in
            let request = PoliMiOAuth.refreshRequest(refreshToken: refreshToken)
            // Deliberately uses the fallback base rather than the live
            // directory: refresh must work before anything else has loaded,
            // and it is the one call that cannot afford a dependency cycle.
            let base = ServiceDirectory.Service.app.fallback
            var components = URLComponents(
                url: base.appendingPathComponent(request.path),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = request.query.isEmpty ? nil : request.query
            var urlRequest = URLRequest(url: components.url!)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            // The only request in the app that had no timeout of its own, and
            // the one every other request waits behind.
            urlRequest.timeoutInterval = 20

            let (data, response) = try await refreshSession.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AuthError.sessionExpired
            }
            return try JSONDecoder().decode(PoliMiToken.self, from: data)
        }

        // `profileID` is read through a closure so the API client always sees
        // the current value, not whatever it was at construction.
        let box = ProfileBox()
        self.profileBox = box
        self.api = PoliMiAPI(
            tokens: tokens,
            directory: directory,
            profileID: { await box.value },
            matricola: { await box.matricola },
            onInvalidScope: { [weak self] in
                // Deliberately does NOT sign the user out.
                //
                // The token is genuinely valid — /jaf/internal/user and
                // /jaf/internal/profiles accept it — so the person is signed
                // in. Only the api.polimi.it services refuse it. Signing out
                // produced a loop: login, 401, sign out, login, and the user
                // never got anywhere. Flag it instead and let them choose to
                // retry the login from Settings.
                await MainActor.run { self?.serviceAuthorizationFailed = true }
            }
        )

        // Last, because it takes `self`: everything it reaches for is built.
        self.login = LoginFlow(session: self)
    }

    /// The OAuth configuration in force, for the views that drive their own flow.
    var oauthParams: ServiceDirectory.OAuthParams { directory.oauth }

    /// The access token currently held, refreshing if necessary.
    ///
    /// The identity provider requires it as proof of identity when moving a grant to
    /// another enrolment. `nil` when there is no usable token.
    var currentAccessToken: String? {
        get async { try? await tokens.validToken() }
    }

    /// Reads `/jaf/internal/profiles` to learn which profile to present, and the
    /// account's secondary profile.
    ///
    /// The student profile is preferred when the account holds several. A failure, or a
    /// payload with no usable profile, leaves ``profileID`` as it was.
    func loadProfile() async {
        do {
            let data = try await api.send(APIRequest(host: .app, path: "/jaf/internal/profiles"))
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            log.notice("profiles payload: \(raw, privacy: .public)")

            if let list = try? JSONDecoder().decode([PoliMiProfileDTO].self, from: data) {
                directory.dProfile = list.compactMap(\.dprofile).first
                let ids = list.compactMap(\.identifier)
                // Prefer the student profile when the account has several.
                if let chosen = ids.first(where: { $0 == PoliMiProfile.student }) ?? ids.first {
                    profileID = chosen
                    await profileBox.set(chosen)
                    log.notice("Using poliAuthProfile \(chosen, privacy: .public)")
                    return
                }
            }
            log.notice("Could not read a profile id; keeping \(self.profileID, privacy: .public)")
        } catch {
            log.error("profiles fetch failed: \(error.localizedDescription)")
        }
    }

    /// Enters ``State/signedIn(_:)`` and brings everything keyed by matricola into
    /// step: the transport's query parameter and the app group's ``SharedAccount``,
    /// which is how the widgets know whose records to read.
    ///
    /// Centralised because there are four ways in — a restore, two exchange paths and
    /// sample data — and a matricola set at three of them would fail only on the
    /// fourth.
    ///
    /// - Parameter student: Who the token belongs to.
    func signIn(_ student: Student) async {
        state = .signedIn(student)
        await profileBox.set(matricola: student.matricola)
        // Widgets read the offline files, which are keyed by matricola, and
        // have no session of their own to ask.
        SharedAccount.update(matricola: student.matricola, firstName: student.firstName)
    }

    /// Moves the session to another state. The only way to do so from outside this
    /// file, which is ``LoginFlow`` and nothing else.
    ///
    /// - Parameter newState: Where the session now stands.
    func enter(_ newState: State) { state = newState }

    /// The signed-in student, or `nil` in any state but ``State/signedIn(_:)``.
    var student: Student? {
        if case .signedIn(let student) = state { return student }
        return nil
    }
}

/// Carries the profile id and the matricola across actor boundaries, so
/// ``PoliMiAPI`` — which is not main-actor bound — can read the current values
/// without capturing ``Session``.
///
/// Read through closures, so the transport always sees the current value rather
/// than whatever it was when the transport was built.
actor ProfileBox {
    /// The value to send as `poliAuthProfile`.
    private(set) var value: Int = PoliMiProfile.default
    /// Updates the profile id.
    ///
    /// - Parameter newValue: The value to send.
    func set(_ newValue: Int) { value = newValue }

    /// The signed-in matricola, for the services that take it as a query parameter, or
    /// `nil` when signed out.
    private(set) var matricola: String?
    /// Updates the matricola.
    ///
    /// - Parameter newValue: The matricola, or `nil` when signed out.
    func set(matricola newValue: String?) { matricola = newValue }
}
