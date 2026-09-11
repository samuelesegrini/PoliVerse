import Foundation
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

    private(set) var state: State = .loading

    /// Set when the app is built without a live backend, so every screen renders
    /// with representative data. Toggled in Settings; defaults on until the
    /// endpoints below are verified against a real account.
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
    private var profileBox: ProfileBox!

    init() {
        self.useMockData = UserDefaults.standard.object(forKey: "useMockData") as? Bool ?? true

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
    }

    /// Decides the opening screen: a stored token means we can go straight in.
    func restore() async {
        // Learn where the services live before calling any of them.
        await directory.load()

        if useMockData {
            state = .signedIn(MockData.student)
            return
        }
        guard await tokens.hasToken else {
            state = .signedOut
            return
        }

        // A token only carries the scopes it was granted at creation; refreshing
        // never widens them. If the Politecnico has added a scope since this
        // token was minted, it will 401 on the new service indefinitely, so
        // re-authenticate rather than leave the user on a half-broken session.
        //
        // A nil recorded scope counts as a mismatch, not as "fine": every token
        // minted before the app started recording it is precisely the token
        // that predates the scope change, so `if let` would skip exactly the
        // case this check exists for.
        let currentScope = directory.oauth.scope
        let granted = await tokens.grantedScope
        if granted != currentScope {
            log.notice("Stored token scope differs from current (had scope: \(granted != nil, privacy: .public)); re-authenticating")
            await tokens.clear()
            state = .signedOut
            return
        }
        do {
            let dto = try await api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            state = .signedIn(dto.toStudent())
            await loadProfile()
        } catch {
            log.error("Restore failed: \(error.localizedDescription)")
            state = .signedOut
        }
    }

    /// Prepares for a genuinely fresh login.
    ///
    /// Does two things the user cannot do from inside the app:
    ///
    /// 1. Deletes any stored token. A token's scopes are fixed at creation and
    ///    refreshing never widens them, so carrying one across a scope change
    ///    keeps the old grant alive forever.
    /// 2. Resolves the `aunicalogin` logout URL, so the login can end the SSO
    ///    session before authorizing. With that session live the IdP may
    ///    re-issue a code against the existing grant and ignore the wider scope
    ///    we ask for — which is how "log in again" can return the same narrow
    ///    token.
    ///
    /// - Returns: the logout URL, or nil to authorize directly.
    func prepareForLogin() async -> URL? {
        await directory.load()
        await tokens.clear()

        do {
            let link = try await api.send(
                PoliMiOAuth.logoutLinkRequest(serviceID: directory.oauth.serviceID),
                as: PoliMiOAuth.LogoutLink.self
            )
            guard let target = link.targetURL, let url = URL(string: target) else {
                log.notice("No SSO logout URL returned; authorizing directly")
                return nil
            }
            log.info("Ending SSO session before authorizing")
            return url
        } catch {
            // Not fatal: without it the login may reuse the old grant, but it
            // is still better to try than to block the user entirely.
            log.error("Could not resolve the SSO logout URL: \(error.localizedDescription)")
            return nil
        }
    }

    /// Adopts a credential minted by the official web app.
    ///
    /// No code exchange: the app already did it, and the token it produced is
    /// one the data services accept — which the one we minted ourselves was
    /// not. See ``PoliMiAppLoginWebView`` for what was ruled out first.
    func completeLogin(token: PoliMiToken) async {
        state = .exchangingCode
        await directory.load()
        await tokens.set(token)
        await tokens.setGrantedScope(directory.oauth.scope)

        do {
            let dto = try await api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            state = .signedIn(dto.toStudent())
            serviceAuthorizationFailed = false
            await loadProfile()
        } catch {
            log.error("Could not read the user after login: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Exchanges the authcode from the web flow for a token pair.
    func completeLogin(authCode: String) async {
        state = .exchangingCode
        // The login web view may have been opened before the directory landed.
        await directory.load()
        do {
            let token = try await api.send(
                PoliMiOAuth.tokenExchangeRequest(authCode: authCode),
                as: PoliMiToken.self
            )
            await tokens.set(token)
            await tokens.setGrantedScope(directory.oauth.scope)

            let dto = try await api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            state = .signedIn(dto.toStudent())
            serviceAuthorizationFailed = false
            await loadProfile()
        } catch {
            log.error("Code exchange failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        serviceAuthorizationFailed = false
        // Server-side invalidation, as the official app does. Best effort: the
        // local token is dropped either way.
        if await tokens.hasToken {
            _ = try? await api.send(PoliMiOAuth.revokeRequest)
        }
        await tokens.clear()
        state = useMockData ? .signedIn(MockData.student) : .signedOut
    }

    /// Reads `/jaf/internal/profiles` to learn which profile to present.
    ///
    /// The response shape is unverified, so the raw body is logged once: that
    /// log line is what turns the guesswork in ``PoliMiProfileDTO`` into a
    /// definite answer.
    private func loadProfile() async {
        do {
            let data = try await api.send(APIRequest(host: .app, path: "/jaf/internal/profiles"))
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            log.notice("profiles payload: \(raw, privacy: .public)")

            if let list = try? JSONDecoder().decode([PoliMiProfileDTO].self, from: data) {
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
}
