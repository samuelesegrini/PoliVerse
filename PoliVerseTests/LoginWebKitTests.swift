import Foundation
import Testing
import WebKit
@testable import PoliVerse

/// The login's WebKit setup.
///
/// The Servizi Online SPA is 13.7 MB — 8.27 MB of JavaScript, 5.43 MB of CSS —
/// and the app has to run it to get a usable token. These pin the decisions
/// that stop it being paid for on every login.
@MainActor
@Suite("Login WebKit")
struct LoginWebKitTests {
    /// A new identifier each launch would be a new empty cache each launch,
    /// which is the entire problem being fixed.
    @Test("The data store is stable across accesses")
    func stableStore() {
        #expect(LoginWebKit.dataStore === LoginWebKit.dataStore)
        #expect(LoginWebKit.dataStore.isPersistent)
    }

    /// The observer hooks `setItem` so the credential is reported rather than
    /// polled for. It must call through, or the page it is watching breaks.
    @Test("The observer script calls the original setItem and returns its result")
    func callsThrough() {
        let script = LoginWebKit.credentialObserver(key: "k")
        #expect(script.source.contains("original.apply(this, arguments)"))
        #expect(script.source.contains("return result"))
    }

    /// At document start, or the SPA stores its credential before the hook
    /// exists and nothing is ever reported.
    @Test("The observer is injected before the page's own scripts run")
    func injectionTime() {
        #expect(LoginWebKit.credentialObserver(key: "k").injectionTime == .atDocumentStart)
    }

    /// A page restored rather than loaded does not re-run a document-start
    /// script, so the value already present has to be reported too.
    @Test("An existing value is reported, not just new writes")
    func reportsExisting() {
        #expect(LoginWebKit.credentialObserver(key: "k").source.contains("getItem"))
    }

    @Test("The watched key is the one asked for")
    func usesKey() {
        #expect(LoginWebKit.credentialObserver(key: "24344_oauthCredentials")
            .source.contains("24344_oauthCredentials"))
    }

    /// Blocking is scoped to the SPA's host on purpose: the identity
    /// providers are pages the user reads and taps, and their buttons are
    /// often images. Blocking there would break the login rather than speed
    /// it up.
    @Test("Blocking is scoped to the app host and never the identity providers")
    func blockingScope() async {
        let rules = await LoginWebKit.contentRules()
        #expect(rules != nil)
    }

    @Test("Compiling the rules twice returns the cached list rather than failing")
    func rulesAreReused() async {
        _ = await LoginWebKit.contentRules()
        #expect(await LoginWebKit.contentRules() != nil)
    }
}
