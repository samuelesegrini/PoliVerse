import Testing
import Foundation
@testable import PoliVerse

/// The refresh-coalescing behaviour is the whole reason ``TokenStore`` is an
/// actor, so it is worth asserting rather than assuming.
@Suite("Token refresh", .tags(.timing, .persistence))
struct TokenStoreTests {
    /// Counts refresh calls across concurrent callers.
    actor RefreshCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private func expiredToken() -> PoliMiToken {
        PoliMiToken(
            accessToken: "stale",
            refreshToken: "refresh-me",
            expiresIn: 3600,
            issuedAt: Date(timeIntervalSinceNow: -7200) // already past expiry
        )
    }

    @Test("Concurrent callers share one refresh")
    func concurrentCallersCoalesce() async throws {
        let counter = RefreshCounter()

        let store = TokenStore(storage: InMemoryTokenPersistence(initial: expiredToken())) { _ in
            await counter.increment()
            // Hold the refresh open so every caller piles up behind it, which
            // is the situation that produced duplicate refreshes in PoliFemo.
            try await Task.sleep(nanoseconds: 120_000_000)
            return PoliMiToken(accessToken: "fresh", refreshToken: "next", expiresIn: 3600)
        }

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 {
                group.addTask { try await store.validToken() }
            }
            var seen: [String] = []
            for try await token in group { seen.append(token) }
            return seen
        }

        #expect(tokens.count == 12)
        #expect(tokens.allSatisfy { $0 == "fresh" })
        // The point of the exercise: one network refresh, not twelve.
        #expect(await counter.count == 1)
    }

    /// The server's refresh answer carries no scope. Losing the recorded one made
    /// every launch after a refresh read a scope change and sign the student out.
    @Test("A refresh keeps the scope the pair was granted")
    func refreshKeepsScope() async throws {
        var stale = expiredToken()
        stale.grantedScope = "openid polimi_app agenda"
        let storage = InMemoryTokenPersistence(initial: stale)
        let store = TokenStore(storage: storage) { _ in
            PoliMiToken(accessToken: "fresh", refreshToken: "next", expiresIn: 3600)
        }

        #expect(try await store.validToken() == "fresh")
        #expect(await store.grantedScope == "openid polimi_app agenda")
        #expect(try await store.forceRefresh() == "fresh")
        #expect(await store.grantedScope == "openid polimi_app agenda", "Anche il refresh forzato")
    }

    /// A launch opens on the student kept with the pair; a refresh dropping them
    /// would send the next launch back to waiting on the network.
    @Test("A refresh keeps the student and profile remembered with the pair")
    func refreshKeepsStudent() async throws {
        let storage = InMemoryTokenPersistence(initial: expiredToken())
        let store = TokenStore(storage: storage) { _ in
            PoliMiToken(accessToken: "fresh", refreshToken: "next", expiresIn: 3600)
        }
        await store.remember(Student.sample)
        await store.remember(profileID: 7)

        #expect(try await store.validToken() == "fresh")
        #expect(await store.student == Student.sample)
        #expect(await store.profileID == 7)
        // And across a launch: the persisted record carries them.
        #expect(storage.load()?.student == Student.sample)
        let reloaded = try JSONDecoder().decode(
            PoliMiToken.Stored.self, from: JSONEncoder().encode(PoliMiToken.Stored(try #require(storage.load()))))
        #expect(reloaded.token.student == Student.sample)
        #expect(reloaded.token.profileID == 7)
    }

    /// The remembered student is what a launch signs in as before asking anyone,
    /// so it must go wherever the pair goes.
    @Test("A refused refresh forgets the student with the pair")
    func refusalForgetsStudent() async {
        struct Refused: Error {}
        let store = TokenStore(storage: InMemoryTokenPersistence(initial: expiredToken())) { _ in throw Refused() }
        await store.remember(Student.sample)

        _ = try? await store.validToken()

        #expect(await store.student == nil)
    }

    /// Only a refusal signs a remembered student out; not reaching the
    /// Politecnico says nothing about the grant.
    @Test("Only a refused token counts as signed out at launch")
    func refusalIsNotOffline() {
        #expect(LoginFlow.refusesToken(AuthError.sessionExpired))
        #expect(LoginFlow.refusesToken(APIError.invalidScope))
        #expect(LoginFlow.refusesToken(APIError.badStatus(401, body: "")))
        #expect(!LoginFlow.refusesToken(APIError.transport(URLError(.notConnectedToInternet))))
        #expect(!LoginFlow.refusesToken(URLError(.timedOut)))
        #expect(!LoginFlow.refusesToken(APIError.badStatus(503, body: "")))
    }

    /// Records written before the student was kept still decode, as a pair with
    /// nobody remembered, so the first launch after the update confirms as before.
    @Test("A stored pair from before decodes with no student")
    func oldRecordDecodes() throws {
        let old = Data(#"{"accessToken":"a","refreshToken":"r","expiresIn":3600,"issuedAt":0,"grantedScope":"s"}"#.utf8)
        let token = try JSONDecoder().decode(PoliMiToken.Stored.self, from: old).token
        #expect(token.student == nil)
        #expect(token.grantedScope == "s")
    }

    @Test("A valid token is returned without refreshing")
    func validTokenSkipsRefresh() async throws {
        let counter = RefreshCounter()
        let valid = PoliMiToken(accessToken: "good", refreshToken: "r", expiresIn: 3600)
        let store = TokenStore(storage: InMemoryTokenPersistence(initial: valid)) { _ in
            await counter.increment()
            return PoliMiToken(accessToken: "fresh", refreshToken: "next", expiresIn: 3600)
        }

        #expect(try await store.validToken() == "good")
        #expect(await counter.count == 0)
    }

    @Test("A failed refresh clears the session instead of looping")
    func failedRefreshClears() async throws {
        struct Boom: Error {}
        let store = TokenStore(storage: InMemoryTokenPersistence(initial: expiredToken())) { _ in
            throw Boom()
        }

        await #expect(throws: AuthError.sessionExpired) {
            _ = try await store.validToken()
        }
        #expect(await store.hasToken == false)
    }

    @Test("With no token at all, callers get notAuthenticated")
    func noTokenThrows() async {
        let store = TokenStore(storage: InMemoryTokenPersistence()) { _ in
            PoliMiToken(accessToken: "x", refreshToken: "y", expiresIn: 60)
        }

        await #expect(throws: AuthError.notAuthenticated) {
            _ = try await store.validToken()
        }
    }

    @Test("Tokens expire early, so a request in flight cannot outlive them")
    func leewayMarksNearExpiryStale() {
        let almostGone = PoliMiToken(
            accessToken: "a", refreshToken: "b", expiresIn: 30, issuedAt: .now
        )
        #expect(almostGone.isExpired())            // inside the 60s leeway
        #expect(almostGone.isExpired(leeway: 0) == false)
    }
}
