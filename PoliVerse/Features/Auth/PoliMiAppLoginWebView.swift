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
    /// Which authorisation this web view is driving. A login by default;
    /// `.login(hintMatricola:)` to land on a particular enrolment, or
    /// `.careerChange` to move an existing grant without signing in again.
    var flow: PoliMiOAuth.AuthorizationFlow = .login()
    /// How the student chose to identify themselves, on our screen rather
    /// than on the Politecnico's. The matching button on the chooser page is
    /// pressed from underneath; see ``PoliMiLoginMethod``.
    var method: PoliMiLoginMethod = .password

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "oauth")

    private let appURL = URL(string: "https://polimiapp.polimi.it/polimi_app/app/")!
    private let credentialsKey = "24344_oauthCredentials"
    private let stateKey = "24344_oauthCheck"

    @State private var state = UUID().uuidString
    @State private var didStartAuthorize = false
    @State private var didFinish = false
    /// The page currently loaded, which is what decides whether the student is
    /// looking at the web view or at our own waiting screen.
    @State private var currentURL: URL?
    /// The chooser is pressed once. It is re-rendered on the way back from a
    /// failed provider login, and pressing again would trap someone who wants
    /// to pick differently.
    @State private var didSelectMethod = false

    /// Set when the chooser's markup has moved under us and the button could
    /// not be pressed. From then on the page is shown as the Politecnico wrote
    /// it: a login that looks less like ours is much better than one that does
    /// not happen.
    @State private var selectionFailed = false

    private var stage: LoginStage {
        LoginStage(url: currentURL, method: method, hasPressed: didSelectMethod)
    }
    private var showsWebView: Bool { selectionFailed || stage.showsWebView }

    var body: some View {
        AuthWebView(
            startURL: appURL,
            router: router,
            // The app drives its own navigation; the authorize redirect must
            // reach it rather than being intercepted by us, because the app is
            // the thing doing the code exchange.
            decide: { _ in .allow },
            onError: onError,
            onCieIDMissing: {
                // The hand-off cannot happen, so nothing more will navigate.
                // Showing the page puts the student back on the Politecnico's
                // own CIE screen, which offers the credential route the page
                // itself recommends for this app.
                selectionFailed = true
                onCieIDMissing()
            },
            onFinished: { webView, url in
                currentURL = url
                guard !didFinish else { return }
                // Built from `url` rather than read back from `currentURL`:
                // the assignment above is a `@State` write and is not visible
                // to this closure until the next render.
                let settled = LoginStage(
                    url: url, method: method, hasPressed: didSelectMethod)
                // Only the chooser carries the buttons. An interstitial on the
                // same host would find nothing to press, and latching the
                // failure there would show the student the raw page before the
                // chooser had even rendered.
                if settled.isChooser {
                    Task { await applyMethod(webView, trimming: settled.trimsPage) }
                }
                guard url?.host == "polimiapp.polimi.it" else { return }
                Task { await advance(webView, url: url) }
            },
            // Pushed, not polled: the page tells us the moment it stores the
            // credential.
            onCredential: { raw in adopt(raw) },
            credentialKey: credentialsKey
        )
        // Hidden until the student is somewhere that has to be theirs. What
        // is covered is the bootstrap, the chooser our own buttons replaced,
        // and the redirect chain that exchanges the code — none of which
        // anyone can act on, and all of which used to be the login.
        .opacity(showsWebView ? 1 : 0)
        .accessibilityHidden(!showsWebView)
        .overlay {
            if !showsWebView {
                LoginWaitingView(method: method)
            }
        }
    }

    /// Presses the button for the method chosen on our screen, and trims the
    /// page when the method's own form is part of it.
    @MainActor
    private func applyMethod(_ webView: WKWebView, trimming: Bool) async {
        if trimming, let css = method.pageTrimmingCSS {
            // Applied every time the chooser renders, not once: the page comes
            // back after a wrong password, and it comes back untrimmed.
            let script = """
            (function () {
              var id = 'poliverse-trim';
              if (document.getElementById(id)) { return; }
              var style = document.createElement('style');
              style.id = id;
              style.textContent = `\(css)`;
              document.head.appendChild(style);
            })()
            """
            _ = try? await webView.evaluateJavaScript(script)
        }

        guard !didSelectMethod, !method.selectionScript.isEmpty else { return }
        didSelectMethod = true
        let pressed = (try? await webView.evaluateJavaScript(method.selectionScript)) as? Bool
        if pressed != true {
            // The button was not found: the page's markup has moved. Showing
            // the chooser is a worse experience and a working one, which is
            // the right way round for a login.
            log.notice("Could not press \(method.id, privacy: .public); showing the page")
            selectionFailed = true
            return
        }

        // CIE is exempt, and has to be: the hand-off to the CieID app is
        // intercepted rather than navigated, so the page legitimately never
        // moves, and the round trip through card and PIN always outlasts any
        // timeout worth having. A watchdog here would fire on every successful
        // CIE login and drop the student back onto the raw chooser.
        if case .cie = method { return }
        // Pressed, and now nothing is guaranteed to happen. A click that
        // submits no form leaves the page exactly where it was, which means no
        // further navigation, no further callback, and our spinner over a page
        // that is waiting for the student. Six seconds is longer than the form
        // post takes on a bad connection and far shorter than anyone's patience
        // with a screen that never changes.
        let pressedURL = currentURL
        Task {
            try? await Task.sleep(for: .seconds(6))
            guard !didFinish, currentURL == pressedURL else { return }
            log.notice("\(method.id, privacy: .public) pressed but the page did not move; showing it")
            selectionFailed = true
        }
    }

    @MainActor
    private func advance(_ webView: WKWebView, url: URL?) async {
        log.debug("Settled on \(url?.path ?? "?", privacy: .public) (authorizing: \(didStartAuthorize, privacy: .public))")

        // Already done? Nothing to do — and this also stops a late navigation
        // restarting the flow.
        if await harvest(from: webView) { return }

        // Once the flow is under way, every arrival back here is a chance for
        // the credential to have appeared.
        //
        // Deliberately not conditional on `?code=` being in the URL: the app is
        // a single-page app and rewrites its own address once it has consumed
        // the code, so by the time the page settles the parameter is usually
        // gone. Keying off it meant the one navigation that mattered fell
        // through to a silent return, and the login simply stopped.
        if didStartAuthorize {
            // The observer script reports the credential the instant it is
            // written, so there is nothing to wait for here. This remains only
            // as the backstop for a page restored from the back-forward cache,
            // where a document-start script does not run again — one check,
            // not twenty-five.
            _ = await harvest(from: webView)
            return
        }

        didStartAuthorize = true

        // Seed the state the app will validate the redirect against. Without
        // it the app rejects a flow it did not start itself.
        let seed = "window.sessionStorage.setItem('\(stateKey)', '\(state)')"
        _ = try? await webView.evaluateJavaScript(seed)

        let authorize = PoliMiOAuth.authorizationURL(
            params: oauthParams, state: state, flow: flow)
        if let matricola = flow.matricola {
            log.notice("Authorizing for matricola \(matricola, privacy: .public) (\(oauthParams.scope.split(separator: " ").count, privacy: .public) scopes)")
        } else {
            log.notice("Handing the official app an authorize flow (\(oauthParams.scope.split(separator: " ").count, privacy: .public) scopes)")
        }
        webView.load(URLRequest(url: authorize))
    }

    /// Accepts a credential handed over by the observer script.
    ///
    /// Idempotent: the script can fire more than once — a restored page posts
    /// what it already had, and the SPA may rewrite the value — and completing
    /// a login twice would exchange the same grant twice.
    @MainActor
    private func adopt(_ raw: String) {
        guard !didFinish,
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return }
        didFinish = true
        log.notice("Credential reported by Servizi Online")
        Task {
            // The session dies with the flow, as it always did; the cache does
            // not, which is what makes the next login fast.
            await LoginWebKit.endSession()
        }
        onCredentials(stored.token)
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
        Task { await LoginWebKit.endSession() }
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
