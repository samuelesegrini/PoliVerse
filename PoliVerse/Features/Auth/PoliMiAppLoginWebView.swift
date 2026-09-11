import SwiftUI
import OSLog
@preconcurrency import WebKit

/// Signs in by running the **official Servizi Online web app** and reading the
/// credential it mints.
///
/// ## Why not do the OAuth ourselves
///
/// We did, and the token it produced was refused by every data service with
/// "Scope OAuth non valido … Code: 33" while authenticating correctly against
/// `/jaf/internal/user`. Ruled out by experiment, in order: the scope string
/// (logged, 33 scopes including `agenda`), `al_id_srv` (the IdP drops it —
/// probing with and without returns a byte-identical redirect), query
/// encoding, ending the SSO session first, the `poliAuthProfile` header, and
/// the web view's cookies (14 adopted, no change).
///
/// Whatever binds a usable grant, it is something the official client does
/// that is not visible in its authorize request. So rather than keep guessing,
/// this loads the real app and takes the token it ends up with — the same
/// approach `myPoliFile` uses against WeBeep, and the only one that cannot
/// diverge from the client that works.
///
/// The app stores credentials in `sessionStorage` under
/// `{REACT_APP_C_APP}_oauthCredentials` — `24344_oauthCredentials` — as
/// `{accessToken, refreshToken, accessTokenExpiration}`. Verified in the
/// bundle: `Px.calculateKey` prefixes every key with `REACT_APP_C_APP + "_"`,
/// and `persistOAuthCredentials` writes `Kpe = "oauthCredentials"` there.
struct PoliMiAppLoginWebView: View {
    let router: CieIDRouter
    let onCredentials: (PoliMiToken) -> Void
    let onError: (any Error) -> Void
    var onCieIDMissing: () -> Void = {}

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "oauth")

    /// Where the official SPA lives.
    private var appURL: URL {
        URL(string: "https://polimiapp.polimi.it/polimi_app/app/")!
    }

    /// `REACT_APP_C_APP` is 24344 in the shipping bundle.
    private let storageKey = "24344_oauthCredentials"

    var body: some View {
        AuthWebView(
            startURL: appURL,
            router: router,
            // The app navigates itself; we only watch.
            decide: { _ in .allow },
            onError: onError,
            onCieIDMissing: onCieIDMissing,
            onFinished: { webView, url in
                guard url?.host == "polimiapp.polimi.it" else { return }
                Task { await readCredentials(from: webView) }
            }
        )
    }

    /// Reads the credential the app has stored, if it has stored one yet.
    ///
    /// Called on every settled navigation because there is no signal for "the
    /// app finished authenticating" — it is a single-page app, so the login
    /// completes without a page load. Polling the key is the honest way to
    /// notice.
    @MainActor
    private func readCredentials(from webView: WKWebView) async {
        let script = "window.sessionStorage.getItem('\(storageKey)')"
        guard
            let raw = try? await webView.evaluateJavaScript(script) as? String,
            let data = raw.data(using: .utf8),
            let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return }

        log.notice("Read credentials from the official app")
        onCredentials(stored.token)
    }

    /// The shape the app persists.
    ///
    /// `accessTokenExpiration` is an absolute epoch in milliseconds
    /// (`expiresIn * 1000 + Date.now()` in the bundle), so it is converted back
    /// into the relative lifetime the rest of the app expects.
    private struct StoredCredentials: Decodable {
        let accessToken: String
        let refreshToken: String
        let accessTokenExpiration: Double?

        var token: PoliMiToken {
            let remaining = accessTokenExpiration
                .map { ($0 / 1000) - Date.now.timeIntervalSince1970 }
                .map { Int(max($0, 60)) }
            return PoliMiToken(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: remaining ?? 3600
            )
        }
    }
}
