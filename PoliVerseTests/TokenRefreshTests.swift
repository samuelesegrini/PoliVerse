import Foundation
import Synchronization
import Testing
@testable import PoliVerse


/// The Keychain must not be read while the app is launching.
///
/// `TokenStore` is built inside `Session.init()`, which runs inside the App's
/// `init()` — main thread, before the first frame. A Keychain read there is
/// IPC to `securityd`, and it was the one piece of launch work actually worth
/// moving: the JSON caches the app also reads measure about a millisecond,
/// which is not worth touching.
@Suite("Keychain is off the launch path")
struct LazyTokenLoadTests {
    /// Counts reads, which is the whole assertion.
    private final class CountingPersistence: TokenPersistence, @unchecked Sendable {
        private(set) var loads = 0
        var stored: PoliMiToken?

        func load() -> PoliMiToken? {
            loads += 1
            return stored
        }
        func save(_ token: PoliMiToken) { stored = token }
        func delete() { stored = nil }
    }

    /// `nonisolated` so the refresh closure, which is `@Sendable`, can call
    /// it — the project defaults every type to `MainActor`.
    private nonisolated func token() -> PoliMiToken {
        PoliMiToken(accessToken: "a", refreshToken: "r", expiresIn: 3600)
    }

    @Test("Creating the store reads nothing")
    func initDoesNotRead() {
        let storage = CountingPersistence()
        _ = TokenStore(storage: storage) { _ in self.token() }
        #expect(storage.loads == 0)
    }

    @Test("The first use reads, and only once")
    func readsOnceOnDemand() async {
        let storage = CountingPersistence()
        storage.stored = token()
        let store = TokenStore(storage: storage) { _ in self.token() }

        #expect(await store.hasToken)
        #expect(await store.grantedScope == nil)
        _ = try? await store.validToken()
        #expect(storage.loads == 1)
    }

    /// "Not loaded yet" and "signed out" both look like a nil token, so a
    /// write has to mark the store loaded or the next read would go back to
    /// the Keychain and resurrect what was just cleared.
    @Test("Clearing is not undone by a later read")
    func clearSticks() async {
        let storage = CountingPersistence()
        storage.stored = token()
        let store = TokenStore(storage: storage) { _ in self.token() }

        await store.clear()
        #expect(!(await store.hasToken))
        #expect(storage.loads == 0)
    }

    @Test("A token set before any read is the one used")
    func setBeforeRead() async {
        let storage = CountingPersistence()
        storage.stored = PoliMiToken(accessToken: "old", refreshToken: "r", expiresIn: 3600)
        let store = TokenStore(storage: storage) { _ in self.token() }

        await store.set(PoliMiToken(accessToken: "new", refreshToken: "r2", expiresIn: 3600))
        #expect((try? await store.validToken()) == "new")
        #expect(storage.loads == 0)
    }
}

/// Refreshing without a network must not end the session.
///
/// `validToken()` refreshed when the access token had expired and, on any
/// failure, called `clear()` — deleting the token from the Keychain and
/// routing the user back to login. In aeroplane mode that is catastrophic:
/// pulling to refresh with an expired token **signed the student out**, and
/// signing back in means the whole CIE dance with a card and a PIN.
///
/// A transport failure and a rejected refresh token are not the same event.
/// One says "not now", the other says "never again".
@Suite("Offline refresh keeps the session")
struct OfflineRefreshTests {
    private final class Persistence: TokenPersistence, @unchecked Sendable {
        var stored: PoliMiToken?
        var deleted = false
        func load() -> PoliMiToken? { stored }
        func save(_ token: PoliMiToken) { stored = token }
        func delete() { deleted = true; stored = nil }
    }

    /// Already expired, so every call attempts a refresh.
    private nonisolated func expired() -> PoliMiToken {
        PoliMiToken(accessToken: "a", refreshToken: "r", expiresIn: -60)
    }

    @Test("A network failure leaves the token in place")
    func offlineKeepsToken() async {
        let storage = Persistence()
        storage.stored = expired()
        let store = TokenStore(storage: storage) { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: (any Error).self) { try await store.validToken() }
        #expect(!storage.deleted)
        #expect(await store.hasToken)
    }

    @Test("A timeout leaves the token in place too")
    func timeoutKeepsToken() async {
        let storage = Persistence()
        storage.stored = expired()
        let store = TokenStore(storage: storage) { _ in throw URLError(.timedOut) }

        await #expect(throws: (any Error).self) { try await store.validToken() }
        #expect(!storage.deleted)
    }

    /// The case the clearing was written for, which still has to work: the
    /// Politecnico refusing the refresh token means the session really is over.
    @Test("A rejected refresh token still ends the session")
    func rejectedClearsToken() async {
        let storage = Persistence()
        storage.stored = expired()
        let store = TokenStore(storage: storage) { _ in throw AuthError.sessionExpired }

        await #expect(throws: (any Error).self) { try await store.validToken() }
        #expect(storage.deleted)
        #expect(!(await store.hasToken))
    }

    /// A failed offline refresh must not poison later attempts: once the
    /// network is back, the same stored refresh token has to be usable.
    @Test("A later attempt can succeed after an offline failure")
    func recoversWhenBack() async {
        let storage = Persistence()
        storage.stored = expired()
        let offline = Mutex(true)
        let store = TokenStore(storage: storage) { _ in
            if offline.withLock({ $0 }) { throw URLError(.notConnectedToInternet) }
            return PoliMiToken(accessToken: "fresh", refreshToken: "r2", expiresIn: 3600)
        }

        await #expect(throws: (any Error).self) { try await store.validToken() }
        offline.withLock { $0 = false }
        #expect((try? await store.validToken()) == "fresh")
    }
}
