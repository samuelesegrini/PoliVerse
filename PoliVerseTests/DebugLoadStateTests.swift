import Testing
@testable import PoliVerse

@Suite("Stati di caricamento forzati")
struct DebugLoadStateTests {
    @Test func readsEachArgument() {
        #expect(DebugLoadState.parse(["PoliVerse", "-ForceLoading"]) == .loading)
        #expect(DebugLoadState.parse(["PoliVerse", "-ForceError"]) == .error)
        #expect(DebugLoadState.parse(["PoliVerse", "-ForceOffline", "-useMockData", "YES"]) == .offline)
    }

    @Test func isInertByDefault() {
        #expect(DebugLoadState.parse([]) == nil)
        #expect(DebugLoadState.parse(["PoliVerse", "-useMockData", "YES", "-ForceSomething"]) == nil)
        // The test run itself is launched without any.
        #expect(DebugLoadState.current == nil)
    }

    @Test func failsAsTheNetworkWould() {
        #expect(DebugLoadState.loading.failure == nil)
        #expect(DebugLoadState.error.failure is APIError)
        #expect(DebugLoadState.offline.failure is APIError)
    }
}
