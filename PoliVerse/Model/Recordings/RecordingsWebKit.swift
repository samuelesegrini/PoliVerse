import OSLog
@preconcurrency import WebKit

/// The web session the lecture recordings run on.
///
/// Recman has no API: it is a set of pages behind the Politecnico's single sign-on,
/// reached through aunicalogin with a ticket. So, unlike every other service in the
/// app, the recordings need a Shibboleth session that outlives a sign-in.
///
/// ``LoginWebKit`` deliberately ends its session when the sign-in finishes, and that
/// stays true. The recordings get a store of their own instead, used by nothing
/// else: it holds what a browser tab on recman would hold, and ``endSession()``
/// empties it when the student signs out. See `docs/recordings.md`, "The session
/// decision".
@MainActor
enum RecordingsWebKit {
    /// Diagnostic log for this type, under the `recordings` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")

    /// Where the archive is entered when the jump from the app's token is refused
    /// (see ``RecmanJump``): aunicalogin's page for recman, which answers with a
    /// ticket for recman when the SSO cookie is present and with the sign-in
    /// otherwise.
    ///
    /// Service 2314 is "Archivio registrazioni didattica", the one the Servizi Online
    /// portal links to. Not 2294, "Registrazioni del corso": that one wants a WeBeep
    /// course (`c_classe_webeep`) and without it recman answers with an error page.
    ///
    /// Asked for in Italian: otherwise the archive follows the account's language, and
    /// ``RecmanParser`` would be reading headers and dates in the other one.
    nonisolated static let entry = URL(string: "https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=\(RecmanJump.serviceID)&lang=IT")!

    /// A persistent store of the recordings' own, under a fixed identifier so the
    /// session survives a relaunch.
    static let dataStore: WKWebsiteDataStore = {
        let identifier = UUID(uuidString: "3B0E6F2C-58A1-4C7D-9E24-6A1D0B8F7C35")!
        return WKWebsiteDataStore(forIdentifier: identifier)
    }()

    /// Removes everything the store holds — cookies, web storage and cache — and the
    /// session kept in the Keychain.
    ///
    /// Called on sign-out, so the next person to sign in on the device cannot reach
    /// the previous student's recordings.
    static func endSession() async {
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        KeychainStore.delete(account: sessionAccount)
        UserDefaults.standard.removeObject(forKey: webexEmailKey)
        restored = false
        log.info("Recordings session cleared")
    }

    /// Where ``RecordingsModel/webexEmail`` is kept.
    nonisolated static let webexEmailKey = "recordingsWebexEmail"

    // MARK: - Keeping the session across launches

    /// The Keychain item the session is kept under.
    private static let sessionAccount = "recordings-session"
    /// How long a kept session is offered back. The Politecnico decides how long it
    /// actually holds; past this, a stale session is not worth restoring.
    private static let sessionLifetime: TimeInterval = 24 * 60 * 60
    /// Whether this process has put the kept session back already.
    private static var restored = false

    /// One cookie, as kept in the Keychain.
    nonisolated struct KeptCookie: Codable, Equatable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let isSecure: Bool
        let isHTTPOnly: Bool
        let sameSite: String?

        /// Takes the parts of a cookie that matter for sending it back.
        init(_ cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path
            isSecure = cookie.isSecure
            isHTTPOnly = cookie.isHTTPOnly
            sameSite = cookie.sameSitePolicy?.rawValue
        }

        /// The cookie again, session-only as it was served.
        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path,
            ]
            if isSecure { properties[.secure] = "TRUE" }
            if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let sameSite { properties[.sameSitePolicy] = sameSite }
            return HTTPCookie(properties: properties)
        }
    }

    /// The session as kept: its cookies and when they were saved.
    nonisolated struct KeptSession: Codable {
        let savedAt: Date
        let cookies: [KeptCookie]
    }

    /// Keeps the session's `polimi.it` and `webex.com` cookies in the Keychain.
    ///
    /// The Politecnico serves every one of them session-only, so WebKit drops them when
    /// the app quits and the student would sign in again at every launch. Kept here, on
    /// this device only, and put back by ``restoreSession()`` — as a browser restores
    /// its tabs. Called after each read that got through, so what is kept is a session
    /// the Politecnico accepted.
    static func saveSession() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("polimi.it") || $0.domain.hasSuffix("webex.com") }
            .map(KeptCookie.init)
        guard !cookies.isEmpty,
              let data = try? JSONEncoder().encode(KeptSession(savedAt: .now, cookies: cookies))
        else { return }
        do {
            try KeychainStore.save(data, account: sessionAccount)
            log.info("Recordings session kept: \(cookies.count, privacy: .public) cookies")
        } catch {
            log.error("Could not keep the recordings session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts the kept session back into ``dataStore``, once per launch.
    ///
    /// A session older than a day is dropped rather than restored. One the
    /// Politecnico has since expired does no harm: the walk ends on the sign-in, as it
    /// would have without it.
    static func restoreSession() async {
        guard !restored else { return }
        restored = true
        guard let data = KeychainStore.load(account: sessionAccount),
              let kept = try? JSONDecoder().decode(KeptSession.self, from: data) else { return }
        guard Date.now.timeIntervalSince(kept.savedAt) < sessionLifetime else {
            KeychainStore.delete(account: sessionAccount)
            log.info("Kept recordings session too old; dropped")
            return
        }
        let store = dataStore.httpCookieStore
        for cookie in kept.cookies.compactMap(\.cookie) {
            await store.setCookie(cookie)
        }
        log.info("Recordings session restored: \(kept.cookies.count, privacy: .public) cookies")
    }

    /// Webex's cookies in the session, for the player to send with the media
    /// requests.
    static func webexCookies() async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies().filter { $0.domain.hasSuffix("webex.com") }
    }

    /// Whether a URL belongs to a sign-in step rather than to recman.
    ///
    /// - Parameter url: The URL to test.
    /// - Returns: `true` for aunicalogin, the Politecnico's identity provider and the
    ///   CIE and SPID providers it hands over to.
    static func isSignIn(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return ["aunicalogin.polimi.it", "shibidp.polimi.it", "cie.polimi.it"].contains(host)
            || !host.hasSuffix("polimi.it")
    }
}
