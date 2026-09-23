import Foundation

/// Owns the OAuth token pair and guarantees at most one refresh in flight.
///
/// An actor, so checking and refreshing is atomic: when several requests meet an
/// expired access token at once, the first starts a refresh and the rest await the
/// same task. That matters because the Politecnico rotates the refresh token, so a
/// second concurrent refresh would present a token the first has already
/// invalidated and end the session.
///
/// ## Failure handling
///
/// A refresh that fails for transport reasons throws ``APIError/transport(_:)`` and
/// leaves the stored pair alone — losing the network must not lose the session. A
/// refresh the identity provider actually refuses clears the pair and throws
/// ``AuthError/sessionExpired``.
///
/// ## Loading
///
/// The Keychain is read on first use rather than at init, because init runs on the
/// main thread before the first frame and a Keychain read is IPC to `securityd`.
actor TokenStore {
    /// The pair in memory, once the Keychain has been read.
    private var token: PoliMiToken?
    /// Whether the Keychain has been consulted. Distinct from ``token`` being `nil`,
    /// which is also what signed out looks like.
    private var didLoad = false
    /// The single refresh in flight, if any. Concurrent callers join it.
    private var refreshTask: Task<PoliMiToken, Error>?

    /// Where the pair lives between launches.
    private let storage: any TokenPersistence
    /// Exchanges a refresh token for a fresh pair. Injected, so the store depends on no
    /// API client.
    private let refresh: @Sendable (String) async throws -> PoliMiToken

    /// Creates a store. The Keychain is not read here; see the type's discussion.
    ///
    /// - Parameters:
    ///   - storage: Where the pair lives between launches. Defaults to the Keychain;
    ///     tests pass ``InMemoryTokenPersistence``.
    ///   - refresh: Performs the refresh network call.
    init(
        storage: any TokenPersistence = KeychainTokenPersistence(),
        refresh: @escaping @Sendable (String) async throws -> PoliMiToken
    ) {
        self.storage = storage
        self.refresh = refresh
        // Deliberately *not* loaded here.
        //
        // This initialiser runs inside `Session.init()`, which runs inside the
        // App's own `init()` — on the main thread, before the first frame.
        // Reading the Keychain means IPC to `securityd`, which is orders of
        // magnitude slower than the JSON caches the app also reads at launch
        // (measured at ~1 ms) and is the one piece of launch work genuinely
        // worth moving.
        //
        // Every accessor is already `async`, so the read happens on first use
        // — which is `Session.restore()`, after the first frame is on screen.
    }

    /// The stored pair, reading it from persistence the first time it is wanted.
    ///
    /// - Returns: The pair, or `nil` when signed out.
    private func current() -> PoliMiToken? {
        if !didLoad {
            token = storage.load()
            didLoad = true
        }
        return token
    }

    /// Whether a token pair is stored.
    var hasToken: Bool { current() != nil }

    /// The scope the stored pair was granted, or `nil` when there is no pair or it
    /// predates scope recording.
    var grantedScope: String? { current()?.grantedScope }

    /// When the stored access token stops working, for the diagnostics page. The token
    /// itself is never exposed; a date is all a bug report needs.
    var expiresAt: Date? { current()?.expiresAt }

    /// Records the scope a freshly exchanged pair was minted with, and persists it.
    ///
    /// Does nothing when there is no stored pair.
    ///
    /// - Parameter scope: The space-separated scope string that was requested.
    func setGrantedScope(_ scope: String) {
        guard var current = current() else { return }
        current.grantedScope = scope
        token = current
        persist()
    }

    /// Replaces the stored pair and persists it.
    ///
    /// - Parameter newToken: The pair to store.
    func set(_ newToken: PoliMiToken) {
        token = newToken
        didLoad = true
        persist()
    }

    /// Discards the pair, cancels any refresh in flight and deletes the persisted copy.
    func clear() {
        token = nil
        didLoad = true
        refreshTask?.cancel()
        refreshTask = nil
        storage.delete()
    }

    /// An access token that is valid now, refreshing once if the stored one has
    /// expired.
    ///
    /// A caller arriving during a refresh awaits that refresh rather than starting its
    /// own.
    ///
    /// - Returns: The access token.
    /// - Throws: ``AuthError/notAuthenticated`` when nothing is stored,
    ///   ``APIError/transport(_:)`` when the refresh never reached the server — the
    ///   stored pair survives — and ``AuthError/sessionExpired`` when the refresh was
    ///   refused, which clears the pair.
    func validToken() async throws -> String {
        guard let current = current() else { throw AuthError.notAuthenticated }

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
            var fresh = try await task.value
            // The server sends back only the pair and its lifetime. The scope is
            // the app's record, and a refresh never widens it, so it carries over;
            // dropping it made the next launch read a scope change and sign out.
            fresh.grantedScope = current.grantedScope
            token = fresh
            persist()
            return fresh.accessToken
        } catch {
            // A transport failure and a rejected refresh token are not the
            // same event: one says "not now", the other "never again".
            //
            // Clearing on *any* failure would mean that pulling to refresh in
            // aeroplane mode with an expired access token deletes the session —
            // and getting back in means the whole CIE dance with a card and a
            // PIN. The network being absent says nothing about whether the
            // grant is still good.
            if Self.isTransport(error) {
                throw APIError.transport(error)
            }
            clear()
            throw AuthError.sessionExpired
        }
    }

    /// Whether a refresh failed because the request never arrived, rather than because
    /// it was refused.
    ///
    /// Cancellation counts: a caller going away is not the Politecnico refusing
    /// anything.
    ///
    /// - Parameter error: The error a refresh threw.
    /// - Returns: `true` for a `URLError`, a cancellation or any error in the URL error
    ///   domain.
    static func isTransport(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if PoliMiAPI.isCancellation(error) { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    /// Refreshes even though the stored access token still looks valid, after a 401
    /// caused by clock skew or by server-side revocation.
    ///
    /// Joins a refresh already in flight rather than starting a second.
    ///
    /// - Returns: The fresh access token.
    /// - Throws: The same errors as ``validToken()``, with the same distinction between
    ///   a transport failure and a refusal.
    func forceRefresh() async throws -> String {
        guard let current = current() else { throw AuthError.notAuthenticated }
        if let existing = refreshTask { return try await existing.value.accessToken }

        let task = Task<PoliMiToken, Error> { [refresh] in
            try await refresh(current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            var fresh = try await task.value
            // The server sends back only the pair and its lifetime. The scope is
            // the app's record, and a refresh never widens it, so it carries over;
            // dropping it made the next launch read a scope change and sign out.
            fresh.grantedScope = current.grantedScope
            token = fresh
            persist()
            return fresh.accessToken
        } catch {
            // Same distinction as `validToken()`: losing the network must not
            // lose the session.
            if Self.isTransport(error) {
                throw APIError.transport(error)
            }
            clear()
            throw AuthError.sessionExpired
        }
    }

    /// Writes the stored pair through ``storage``. Does nothing when there is none.
    private func persist() {
        guard let token else { return }
        storage.save(token)
    }
}

/// Where the token pair is kept between launches.
///
/// ``KeychainTokenPersistence`` is the real one; ``InMemoryTokenPersistence`` keeps
/// tests off the device Keychain.
nonisolated protocol TokenPersistence: Sendable {
    /// Reads the stored pair.
    ///
    /// - Returns: The pair, or `nil` when none is stored or it will not decode.
    func load() -> PoliMiToken?
    /// Stores a pair, replacing any previous one.
    ///
    /// - Parameter token: The pair to store.
    func save(_ token: PoliMiToken)
    /// Removes the stored pair. A missing pair is not an error.
    func delete()
}

/// Token persistence backed by ``KeychainStore``, under the `polimi` account.
///
/// Encodes ``PoliMiToken/Stored``, so the fields the server does not send survive
/// a relaunch.
nonisolated struct KeychainTokenPersistence: TokenPersistence {
    /// The Keychain account the pair is filed under.
    private let account = "polimi"

    /// Reads and decodes the pair from the Keychain.
    ///
    /// - Returns: The pair, or `nil` when absent or undecodable.
    func load() -> PoliMiToken? {
        guard let data = KeychainStore.load(account: account) else { return nil }
        return (try? JSONDecoder().decode(PoliMiToken.Stored.self, from: data))?.token
    }

    /// Encodes and writes the pair to the Keychain. Failures are ignored.
    ///
    /// - Parameter token: The pair to store.
    func save(_ token: PoliMiToken) {
        guard let data = try? JSONEncoder().encode(PoliMiToken.Stored(token)) else { return }
        try? KeychainStore.save(data, account: account)
    }

    /// Removes the pair from the Keychain.
    func delete() {
        KeychainStore.delete(account: account)
    }
}

/// Token persistence that lasts only as long as the process, so tests never touch
/// the device Keychain.
///
/// Guarded by a lock, since ``TokenStore`` calls it from its own executor.
nonisolated final class InMemoryTokenPersistence: TokenPersistence, @unchecked Sendable {
    /// Guards ``stored``.
    private let lock = NSLock()
    /// The held pair.
    private var stored: PoliMiToken?

    /// Creates the store.
    ///
    /// - Parameter initial: The pair to start with, or `nil` for signed out.
    init(initial: PoliMiToken? = nil) { stored = initial }

    /// The held pair, or `nil`.
    func load() -> PoliMiToken? { lock.withLock { stored } }
    /// Replaces the held pair.
    ///
    /// - Parameter token: The pair to hold.
    func save(_ token: PoliMiToken) { lock.withLock { stored = token } }
    /// Discards the held pair.
    func delete() { lock.withLock { stored = nil } }
}

/// What can go wrong with the session itself, as opposed to one request.
nonisolated enum AuthError: LocalizedError, Equatable {
    /// No token pair is stored: nobody is signed in.
    case notAuthenticated
    /// The identity provider refused the refresh token. The stored pair has been
    /// cleared and the student must sign in again.
    case sessionExpired
    /// The student dismissed the sign-in sheet.
    case loginCancelled
    /// The authorisation code could not be exchanged for a token pair, with the reason.
    case codeExchangeFailed(String)

    /// The localised sentence shown to the student.
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: String(localized: "Non hai effettuato l'accesso.")
        case .sessionExpired: String(localized: "La sessione è scaduta. Accedi di nuovo.")
        case .loginCancelled: String(localized: "Accesso annullato.")
        case .codeExchangeFailed(let detail): String(localized: "Accesso non riuscito: \(detail)")
        }
    }
}
