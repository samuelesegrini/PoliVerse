import Foundation
import UserNotifications
import Observation
import OSLog

/// Whether the app has a usable PoliMi session, and who it belongs to.
@Observable
final class Session {
    enum State: Equatable {
        case loading
        case signedOut
        case exchangingCode
        case signedIn(Student)
        case failed(String)
    }

    /// Set by ``Session`` itself and by ``LoginFlow``, which is the only
    /// other thing allowed to move a session between states.
    internal private(set) var state: State = .loading

    /// Set when the app is built without a live backend, so every screen renders
    /// with representative data.
    ///
    /// **Defaults off.** It used to default on, from when the endpoints were
    /// still being verified, and the cost of leaving it that way was that a
    /// fresh install showed invented lectures to someone who had never been
    /// told the setting existed. The first run now asks outright
    /// (``WelcomeStepView``), and the answer is a choice rather than a
    /// leftover.
    var useMockData: Bool {
        didSet { UserDefaults.standard.set(useMockData, forKey: "useMockData") }
    }

    let tokens: TokenStore
    let directory = ServiceDirectory()
    private(set) var api: PoliMiAPI!

    /// Sent as `poliAuthProfile`. Defaults to the student profile and is
    /// refined once `/jaf/internal/profiles` has been read.
    private(set) var profileID: Int = PoliMiProfile.default

    /// True when the Politecnico accepted the login but refuses the token for
    /// its data services ("Scope OAuth non valido … Code: 33").
    ///
    /// Kept separate from ``state`` because the two are genuinely different:
    /// the session is fine, a subset of services is not.
    var serviceAuthorizationFailed = false
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "session")
    var profileBox: ProfileBox!

    /// How the student got in. Owned here, so that the order in which the
    /// session and the login are built cannot come apart.
    private(set) var login: LoginFlow!

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

    /// The OAuth configuration, for views that drive their own flow.
    var oauthParams: ServiceDirectory.OAuthParams { directory.oauth }

    /// The token currently held, which the IdP requires as proof of identity
    /// when moving a grant to another enrolment.
    var currentAccessToken: String? {
        get async { try? await tokens.validToken() }
    }

    /// Reads `/jaf/internal/profiles` to learn which profile to present.
    ///
    /// The response shape is unverified, so the raw body is logged once: that
    /// log line is what turns the guesswork in ``PoliMiProfileDTO`` into a
    /// definite answer.
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

    /// Signs the user in, keeping the matricola the API client reads in step
    /// with the student on screen.
    ///
    /// Centralised because there are four ways in — restore, two exchange
    /// paths and mock data — and a matricola set at three of them would fail
    /// only on the fourth.
    func signIn(_ student: Student) async {
        state = .signedIn(student)
        await profileBox.set(matricola: student.matricola)
        // Widgets read the offline files, which are keyed by matricola, and
        // have no session of their own to ask.
        SharedAccount.update(matricola: student.matricola, firstName: student.firstName)
    }

    /// The only way to move a session between states from outside this file,
    /// which is ``LoginFlow`` and nothing else.
    func enter(_ newState: State) { state = newState }

    var student: Student? {
        if case .signedIn(let student) = state { return student }
        return nil
    }
}

/// Carries the profile id across actor boundaries so ``PoliMiAPI`` — which is
/// not main-actor bound — can read the current value without capturing
/// ``Session``.
actor ProfileBox {
    private(set) var value: Int = PoliMiProfile.default
    func set(_ newValue: Int) { value = newValue }

    /// The signed-in matricola, for the services that take it as a query
    /// parameter. Kept beside the profile because both are known at the same
    /// moment and read the same way — through a closure, so the API client
    /// always sees the current value rather than whatever it was at
    /// construction.
    private(set) var matricola: String?
    func set(matricola newValue: String?) { matricola = newValue }
}
