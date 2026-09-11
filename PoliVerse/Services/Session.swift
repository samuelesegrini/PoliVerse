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
        let store = self.tokens
        self.api = PoliMiAPI(
            tokens: tokens,
            directory: directory,
            profileID: { await box.value },
            onInvalidScope: { [weak self] in
                // The token cannot be repaired, so drop it; the next launch or
                // the next view update lands on the login screen.
                await store.clear()
                await MainActor.run { self?.state = .signedOut }
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
            await loadProfile()
        } catch {
            log.error("Code exchange failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
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
