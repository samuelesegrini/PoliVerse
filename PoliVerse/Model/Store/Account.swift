import Foundation

/// The three facts every load needs to know about who is signed in.
///
/// ``Store`` depends on this rather than on ``Session`` directly, and the
/// reason is testability rather than tidiness. `Session()` builds a
/// ``TokenStore`` over the Keychain, a ``ServiceDirectory``, a ``PoliMiAPI``
/// and a ``LoginFlow`` before it returns — so a test that wanted to exercise a
/// service's load had to stand all of that up first, which is why in practice
/// none of them did. Three properties is a thing a test can fake in four lines.
@MainActor
protocol Account: AnyObject {
    /// The signed-in matricola, or nil when signed out. Offline records are
    /// keyed by it, so nil means "cache nothing, restore nothing".
    var matricola: String? { get }
    /// True when the app is showing representative data rather than this
    /// student's. See ``Session/useMockData``.
    var isSample: Bool { get }
    /// The transport this account's requests go through.
    var http: any HTTP { get }
}

extension Session: Account {
    var isSample: Bool { useMockData }
    var matricola: String? { student?.matricola }
    var http: any HTTP { api }
}

/// An account with nothing behind it, for previews and for tests that only
/// care about one branch of a load.
@MainActor
final class StubAccount: Account {
    var matricola: String?
    var isSample: Bool
    var http: any HTTP

    init(matricola: String? = "123456", isSample: Bool = false, http: any HTTP = FixtureHTTP()) {
        self.matricola = matricola
        self.isSample = isSample
        self.http = http
    }
}
