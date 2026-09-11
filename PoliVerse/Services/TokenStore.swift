import Foundation

/// Owns the token pair and guarantees **at most one refresh in flight**.
///
/// This is the bug PoliFemo left open (`// TODO: await for token to refresh
/// before sending multiple requests` in `HttpClient.ts`). When the home screen
/// fires five requests and the access token has just expired, all five get a
/// 401 and all five call refresh. Because PoliMi rotates the refresh token, the
/// first response invalidates the token the other four are still using — the
/// user is silently logged out mid-session.
///
/// Making this an `actor` means the check-and-refresh is atomic by
/// construction, and callers that arrive during a refresh `await` the same
/// `Task` instead of starting their own.
actor TokenStore {
    private var token: PoliMiToken?
    /// The single in-flight refresh, if any. Concurrent callers join this.
    private var refreshTask: Task<PoliMiToken, Error>?

    private let storage: any TokenPersistence
    private let refresh: @Sendable (String) async throws -> PoliMiToken

    /// - Parameters:
    ///   - refresh: performs the network call. Injected so the store stays
    ///     testable and free of any dependency on the API client.
    ///   - storage: where the token lives between launches. Defaults to the
    ///     Keychain; tests pass an in-memory double so they neither read nor
    ///     write the real one.
    init(
        storage: any TokenPersistence = KeychainTokenPersistence(),
        refresh: @escaping @Sendable (String) async throws -> PoliMiToken
    ) {
        self.storage = storage
        self.refresh = refresh
        self.token = storage.load()
    }

    var hasToken: Bool { token != nil }

    /// The scope the stored token was granted, if any.
    var grantedScope: String? { token?.grantedScope }

    /// Records the scope a freshly-exchanged token was minted with.
    func setGrantedScope(_ scope: String) {
        guard var current = token else { return }
        current.grantedScope = scope
        token = current
        persist()
    }

    func set(_ newToken: PoliMiToken) {
        token = newToken
        persist()
    }

    func clear() {
        token = nil
        refreshTask?.cancel()
        refreshTask = nil
        storage.delete()
    }

    /// Returns a token that is valid *now*, refreshing once if needed.
    func validToken() async throws -> String {
        guard let current = token else { throw AuthError.notAuthenticated }

        if !current.isExpired() { return current.accessToken }

        // Someone is already refreshing — wait for their result rather than
        // racing them.
        if let existing = refreshTask {
            return try await existing.value.accessToken
        }

        let task = Task<PoliMiToken, Error> { [refresh] in
            try await refresh(current.refreshToken)
        }
        refreshTask = task

        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            token = fresh
            persist()
            return fresh.accessToken
        } catch {
            // A failed refresh means the session is dead; drop it so the UI
            // routes back to login instead of retrying forever.
            clear()
            throw AuthError.sessionExpired
        }
    }

    /// Forces a refresh after a 401 that arrived despite a locally-valid token
    /// (clock skew, or server-side revocation).
    func forceRefresh() async throws -> String {
        guard let current = token else { throw AuthError.notAuthenticated }
        if let existing = refreshTask { return try await existing.value.accessToken }

        let task = Task<PoliMiToken, Error> { [refresh] in
            try await refresh(current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            token = fresh
            persist()
            return fresh.accessToken
        } catch {
            clear()
            throw AuthError.sessionExpired
        }
    }

    private func persist() {
        guard let token else { return }
        storage.save(token)
    }
}

/// Where the token pair is kept between launches.
nonisolated protocol TokenPersistence: Sendable {
    func load() -> PoliMiToken?
    func save(_ token: PoliMiToken)
    func delete()
}

/// The real one.
nonisolated struct KeychainTokenPersistence: TokenPersistence {
    private let account = "polimi"

    func load() -> PoliMiToken? {
        guard let data = KeychainStore.load(account: account) else { return nil }
        return (try? JSONDecoder().decode(PoliMiToken.Stored.self, from: data))?.token
    }

    func save(_ token: PoliMiToken) {
        guard let data = try? JSONEncoder().encode(PoliMiToken.Stored(token)) else { return }
        try? KeychainStore.save(data, account: account)
    }

    func delete() {
        KeychainStore.delete(account: account)
    }
}

/// Keeps a token only for the lifetime of the process. Used by tests so they
/// never touch the device Keychain.
nonisolated final class InMemoryTokenPersistence: TokenPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PoliMiToken?

    init(initial: PoliMiToken? = nil) { stored = initial }

    func load() -> PoliMiToken? { lock.withLock { stored } }
    func save(_ token: PoliMiToken) { lock.withLock { stored = token } }
    func delete() { lock.withLock { stored = nil } }
}

nonisolated enum AuthError: LocalizedError, Equatable {
    case notAuthenticated
    case sessionExpired
    case loginCancelled
    case codeExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Non hai effettuato l'accesso."
        case .sessionExpired: "La sessione è scaduta. Accedi di nuovo."
        case .loginCancelled: "Accesso annullato."
        case .codeExchangeFailed(let detail): "Accesso non riuscito: \(detail)"
        }
    }
}
