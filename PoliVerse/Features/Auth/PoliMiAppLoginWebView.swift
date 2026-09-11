import SwiftUI
import OSLog
@preconcurrency import WebKit

/// Signs in by driving the **official Servizi Online web app** and reading the
/// credential it mints.
///
/// ## Why not mint our own token
///
/// We did, repeatedly. A token we mint authenticates correctly against
/// `/jaf/internal/user` and is refused by every data service with
/// "Scope OAuth non valido … Code: 33". Ruled out on a real device, in order:
/// the scope string (logged live — 33 scopes, `agenda` included), `al_id_srv`
/// (the IdP drops it), query encoding, ending the SSO session first, the
/// `poliAuthProfile` header, and the browser cookies (14 adopted). Whatever
/// binds a usable grant is not visible in the authorize request, so this stops
/// guessing and uses the client that works.
///
/// ## How it works
///
/// The app will not log in on its own. Its state machine reads
///
/// ```js
/// bxe() ? "OAUTH_PARAMS" : NEe ? … : "ANONYMOUS"
/// ```
///
/// where `bxe()` is true only when **both** `code` and `state` are present in
/// `window.location.search`, and `NEe`
/// (`REACT_APP_ANONYMOUS_CHECK_SSO`) is false in the shipping build. Loading
/// the app bare therefore lands in anonymous mode and simply sits there — which
/// is exactly what it did.
///
/// So it is handed what it needs, in three steps:
///
/// 1. **Bootstrap** — load the app once, so its origin exists and its
///    `sessionStorage` is writable.
/// 2. **Seed and authorize** — write our `state` into `24344_oauthCheck`, then
///    navigate to the IdP. The app validates the returned `state` against that
///    key (`if (n.state !== t && n.state !== void 0) throw`), so seeding it is
///    what lets an externally-started flow pass its check.
/// 3. **Harvest** — the app exchanges the code itself and stores
///    `{accessToken, refreshToken, accessTokenExpiration}` in
///    `24344_oauthCredentials`. We read it.
///
/// Keys are `REACT_APP_C_APP + "_" + name`, per `Px.calculateKey`.
struct PoliMiAppLoginWebView: View {
    let oauthParams: ServiceDirectory.OAuthParams
    let router: CieIDRouter
    let onCredentials: (PoliMiToken) -> Void
    let onError: (any Error) -> Void
    var onCieIDMissing: () -> Void = {}

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "oauth")

    private let appURL = URL(string: "https://polimiapp.polimi.it/polimi_app/app/")!
    private let credentialsKey = "24344_oauthCredentials"
    private let stateKey = "24344_oauthCheck"

    @State private var state = UUID().uuidString
    @State private var didStartAuthorize = false
    @State private var didFinish = false

    var body: some View {
        AuthWebView(
            startURL: appURL,
            router: router,
            // The app drives its own navigation; the authorize redirect must
            // reach it rather than being intercepted by us, because the app is
            // the thing doing the code exchange.
            decide: { _ in .allow },
            onError: onError,
            onCieIDMissing: onCieIDMissing,
            onFinished: { webView, url in
                guard !didFinish, url?.host == "polimiapp.polimi.it" else { return }
                Task { await advance(webView, url: url) }
            }
        )
    }

    @MainActor
    private func advance(_ webView: WKWebView, url: URL?) async {
        // The app has run its exchange by now if it is going to; check first so
        // a late navigation cannot restart the flow.
        if await harvest(from: webView) { return }

        let hasCode = url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.contains { $0.name == "code" } ?? false

        if hasCode {
            // The app is mid-exchange. It is a single-page app, so there is no
            // further navigation to wait on — poll briefly instead.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(400))
                if await harvest(from: webView) { return }
            }
            log.error("The app received a code but stored no credentials")
            onError(AuthError.codeExchangeFailed("Servizi Online non ha completato l'accesso."))
            return
        }

        guard !didStartAuthorize else { return }
        didStartAuthorize = true

        // Seed the state the app will validate the redirect against.
        let seed = "window.sessionStorage.setItem('\(stateKey)', '\(state)')"
        _ = try? await webView.evaluateJavaScript(seed)

        let authorize = PoliMiOAuth.authorizationURL(params: oauthParams, state: state)
        log.notice("Handing the official app an authorize flow (\(oauthParams.scope.split(separator: " ").count, privacy: .public) scopes)")
        webView.load(URLRequest(url: authorize))
    }

    /// Reads the credential if the app has stored one.
    @MainActor
    private func harvest(from webView: WKWebView) async -> Bool {
        let script = "window.sessionStorage.getItem('\(credentialsKey)')"
        guard
            let raw = try? await webView.evaluateJavaScript(script) as? String,
            let data = raw.data(using: .utf8),
            let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return false }

        didFinish = true
        log.notice("Read credentials minted by the official app")
        onCredentials(stored.token)
        return true
    }

    /// The shape the app persists. `accessTokenExpiration` is an absolute epoch
    /// in milliseconds (`expiresIn * 1000 + Date.now()`), converted back into
    /// the relative lifetime the rest of the app expects.
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
