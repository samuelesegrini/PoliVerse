import Foundation

/// The facts about the signed-in student that every load needs.
///
/// ``Store`` depends on this rather than on ``Session`` so that a load can be
/// exercised without standing up a ``TokenStore``, a ``ServiceDirectory``, a
/// ``PoliMiAPI`` and a ``LoginFlow``. ``Session`` conforms; ``StubAccount``
/// serves previews and tests.
@MainActor
protocol Account: AnyObject {
    /// The signed-in matricola, or `nil` when signed out.
    ///
    /// Offline records are keyed by it, so `nil` means nothing is cached and nothing
    /// is restored.
    var matricola: String? { get }
    /// The person behind the enrolments, which is not the matricola: one person has
    /// a matricola per career.
    ///
    /// Anything remembered per person rather than per career — the chosen career,
    /// for one — is keyed by this.
    var personCode: String? { get }
    /// The student's surname.
    ///
    /// The Manifesti service picks a teaching's alphabetical bracket — the
    /// *scaglione*, which decides the lecturer — from it, so the study plan needs it.
    var lastName: String? { get }
    /// `true` when the app is showing representative data rather than this
    /// student's. See ``Session/useMockData``.
    var isSample: Bool { get }
    /// The transport this account's requests go through.
    var http: any HTTP { get }
}

/// Projects the live session onto the three facts a load needs.
extension Session: Account {
    /// Mirrors ``Session/useMockData``.
    var isSample: Bool { useMockData }
    /// The signed-in student's matricola, or `nil` when signed out.
    var matricola: String? { student?.matricola }
    /// The signed-in student's person code, or `nil` when signed out.
    var personCode: String? { student?.personCode }
    /// The signed-in student's surname, or `nil` when signed out.
    var lastName: String? { student?.lastName }
    /// The session's authenticated ``PoliMiAPI``.
    var http: any HTTP { api }
}

/// An ``Account`` backed by nothing, for previews and for tests that exercise a
/// single branch of a load.
///
/// Every property is settable, and the default transport is ``FixtureHTTP``.
@MainActor
final class StubAccount: Account {
    /// The matricola to report. Settable.
    var matricola: String?
    /// The person code to report. Settable.
    var personCode: String?
    /// The surname to report. Settable.
    var lastName: String?
    /// Whether loads should take the sample-data path. Settable.
    var isSample: Bool
    /// The transport handed to sources. Defaults to ``FixtureHTTP``.
    var http: any HTTP

    /// Creates a stub account.
    ///
    /// - Parameters:
    ///   - matricola: The matricola to report, or `nil` to appear signed out.
    ///   - personCode: The person code to report.
    ///   - lastName: The surname to report.
    ///   - isSample: Whether loads should take the sample-data path.
    ///   - http: The transport to hand to sources.
    init(matricola: String? = "123456", personCode: String? = "p1",
         lastName: String? = "Rossi", isSample: Bool = false,
         http: any HTTP = FixtureHTTP()) {
        self.matricola = matricola
        self.personCode = personCode
        self.lastName = lastName
        self.isSample = isSample
        self.http = http
    }
}
