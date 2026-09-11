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
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "session")

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

        self.api = PoliMiAPI(tokens: tokens, directory: directory)
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
        let currentScope = directory.oauth.scope
        if let granted = await tokens.grantedScope, granted != currentScope {
            log.notice("Stored token predates a scope change; signing out to re-authenticate")
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
        } catch {
            log.error("Code exchange failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        await tokens.clear()
        state = useMockData ? .signedIn(MockData.student) : .signedOut
    }

    var student: Student? {
        if case .signedIn(let student) = state { return student }
        return nil
    }
}
