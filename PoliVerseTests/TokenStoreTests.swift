import Testing
import Foundation
@testable import PoliVerse

/// The refresh-coalescing behaviour is the whole reason ``TokenStore`` is an
/// actor, so it is worth asserting rather than assuming.
@Suite("Token refresh")
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
