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

    private let account = "polimi"
    private let refresh: @Sendable (String) async throws -> PoliMiToken

    /// - Parameter refresh: performs the network call. Injected so the store
    ///   stays testable and free of any dependency on the API client.
    init(refresh: @escaping @Sendable (String) async throws -> PoliMiToken) {
        self.refresh = refresh
        if let data = KeychainStore.load(account: account) {
            self.token = try? JSONDecoder().decode(PoliMiToken.self, from: data)
        }
    }

    var hasToken: Bool { token != nil }

    func set(_ newToken: PoliMiToken) {
        token = newToken
        persist()
    }

    func clear() {
        token = nil
        refreshTask?.cancel()
        refreshTask = nil
        KeychainStore.delete(account: account)
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
        guard let token, let data = try? JSONEncoder().encode(token) else { return }
        try? KeychainStore.save(data, account: account)
    }
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
