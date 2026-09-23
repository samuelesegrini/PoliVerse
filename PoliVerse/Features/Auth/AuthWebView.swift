import SwiftUI
import OSLog
@preconcurrency import WebKit

/// What the host wants done with a navigation.
nonisolated enum AuthWebViewDecision {
    /// Let the web view proceed.
    case allow
    /// The host recognised this URL. Stop navigating and run the action —
    /// which runs *after* the web view's cookies have been adopted, so an
    /// exchange kicked off here inherits the session the login established.
    ///
    /// The action is carried rather than performed inside `decide` so that
    /// deciding stays free of side effects: asking the same question twice must
    /// not fire the action twice.
    case finish(@MainActor () -> Void)
    /// Stop, and load this URL instead.
    case load(URL)
}

/// A login web view that survives the CieID round trip.
///
/// Both the PoliMi OAuth login and the WeBeep Moodle login run through here, so
/// "Entra con CIE" behaves identically in both and the handling exists once.
///
/// See ``CieIDBridge`` for why the hand-off has to be intercepted rather than
/// simply allowed.
struct AuthWebView: UIViewRepresentable {
    /// The page the sign-in begins on.
    let startURL: URL
    /// Carries a CieID return back into this web view, so the session continues where it left
    /// off.
    let router: CieIDRouter
    /// Called for every navigation so the host can spot its own completion URL.
    let decide: (URL) -> AuthWebViewDecision
    /// Called when a navigation genuinely fails — never for a cancel the view asked for.
    let onError: (any Error) -> Void
    /// Called when the IdP hand-off fails because CieID is not installed.
    var onCieIDMissing: () -> Void = {}
    /// Called after each navigation settles, so a host can sequence steps or
    /// inspect the page.
    var onFinished: (WKWebView, URL?) -> Void = { _, _ in }
    /// Called with the raw credential the page stored, the moment it does.
    /// Supplying this installs the observer script; omitting it leaves the
    /// page untouched.
    var onCredential: ((String) -> Void)?
    /// The `sessionStorage` key to watch.
    var credentialKey: String = ""
    /// The store the sign-in runs on. ``LoginWebKit/dataStore`` unless a flow keeps
    /// a session of its own, as the recordings do.
    var dataStore: WKWebsiteDataStore?
    /// Whether finishing copies the session's `polimi.it` cookies into the shared
    /// jar, which the token exchange needs. A flow whose session stays in its own
    /// store turns it off.
    var adoptsCookies = true

    /// Creates the navigation delegate and credential observer.
    ///
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(router: router, decide: decide, onError: onError,
                    onCieIDMissing: onCieIDMissing, onFinished: onFinished, adoptsCookies: adoptsCookies)
    }

    /// Creates the web view on ``LoginWebKit``'s persistent store, with the content rules and,
    /// when ``onCredential`` is supplied, the credential observer.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The web view, loading ``startURL``.
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A persistent store of this app's own, so the 13.7 MB of JavaScript
        // and CSS the Servizi Online SPA weighs is cached between logins
        // rather than downloaded again every time.
        //
        // The non-persistent store this replaced guaranteed that a Shibboleth
        // session could never outlive the login — a property worth keeping,
        // and one that does not require discarding the cache along with it.
        // ``LoginWebKit/endSession()`` deletes the cookies when the flow ends,
        // so the session dies exactly as before.
        //
        // It also fixes a real failure: the CieID detour backgrounds PoliVerse
        // for as long as the card and PIN take, and if iOS reclaimed the app
        // in that window the in-memory cookies went with it and the login had
        // to be restarted from the top.
        configuration.websiteDataStore = dataStore ?? LoginWebKit.dataStore

        // Tells us the instant the credential is written, instead of polling
        // for it.
        if let handler = onCredential {
            configuration.userContentController.addUserScript(
                LoginWebKit.credentialObserver(key: credentialKey))
            configuration.userContentController.add(
                context.coordinator, name: LoginWebKit.messageName)
            context.coordinator.onCredential = handler
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: startURL))

        // Compiled asynchronously; applied as soon as it is ready. The first
        // login of a fresh install may start a moment before the rules exist,
        // which costs bytes rather than correctness.
        Task { @MainActor in
            if let rules = await LoginWebKit.contentRules() {
                webView.configuration.userContentController.add(rules)
            }
        }
        return webView
    }

    /// Loads whatever CieID handed back, once the router has something to consume.
    ///
    /// - Parameters:
    ///   - webView: The web view to update.
    ///   - context: The representable's context.
    func updateUIView(_ webView: WKWebView, context: Context) {
        // A pending URL means CieID just handed control back. Loading it into
        // *this* web view is the whole point — it already holds the session the
        // IdP established.
        //
        // `consume()` clears observable state, which must not happen during a
        // view update, so the whole thing hops to the next runloop turn.
        guard router.pendingURL != nil else { return }
        let router = router
        Task { @MainActor in
            guard let resume = router.consume() else { return }
            context.coordinator.resuming = true
            context.coordinator.log.debug("Resuming session after CieID")
            webView.load(URLRequest(url: resume))
        }
    }

    /// Decides each navigation, intercepts the CieID hand-off, and receives the credential the
    /// page stores.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        /// Called with the raw credential the page stored.
        var onCredential: ((String) -> Void)?

        /// Receives the credential the observer script posts.
        ///
        /// - Parameters:
        ///   - controller: The content controller.
        ///   - message: The posted message, whose body is the stored value.
        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard message.name == LoginWebKit.messageName,
                  let raw = message.body as? String, !raw.isEmpty else { return }
            onCredential?(raw)
        }

        /// Carries a CieID return back into the web view.
        private let router: CieIDRouter
        /// Asks the host what to do with each navigation.
        private let decide: (URL) -> AuthWebViewDecision
        /// Reports a genuine navigation failure.
        private let onError: (any Error) -> Void
        /// Reports that CieID is not installed.
        private let onCieIDMissing: () -> Void
        /// Reports that a navigation has settled.
        private let onFinished: (WKWebView, URL?) -> Void
        /// Whether finishing copies the session's cookies into the shared jar.
        private let adoptsCookies: Bool
        /// Diagnostic log for this type, under the `authweb` category.
        let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "authweb")

        /// The web view being driven, held weakly.
        weak var webView: WKWebView?
        /// `true` while the page CieID handed back is being loaded.
        var resuming = false
        /// `true` once the host has said the flow is over, after which navigations are left alone.
        private var finished = false
        /// Set whenever we cancel a navigation on purpose.
        ///
        /// Cancelling surfaces in `didFailProvisionalNavigation` as
        /// `WebKitErrorDomain` 102 — not as `NSURLErrorCancelled` — so without
        /// this the CIE hand-off reported itself as a login failure and the
        /// host dismissed the web view. CieID would then return to nothing.
        private var cancelledDeliberately = false
        /// URLs we have re-issued ourselves, so the re-issued navigation is
        /// allowed through rather than bouncing forever.
        private var reissued: Set<String> = []

        /// Creates the delegate.
        ///
        /// - Parameters:
        ///   - router: Carries a CieID return back into the web view.
        ///   - decide: Asks the host what to do with each navigation.
        ///   - onError: Reports a genuine failure.
        ///   - onCieIDMissing: Reports that CieID is not installed.
        ///   - onFinished: Reports that a navigation has settled.
        ///   - adoptsCookies: Whether finishing copies the session's cookies into the
        ///     shared jar.
        init(
            router: CieIDRouter,
            decide: @escaping (URL) -> AuthWebViewDecision,
            onError: @escaping (any Error) -> Void,
            onCieIDMissing: @escaping () -> Void,
            onFinished: @escaping (WKWebView, URL?) -> Void,
            adoptsCookies: Bool = true
        ) {
            self.router = router
            self.decide = decide
            self.onError = onError
            self.onCieIDMissing = onCieIDMissing
            self.onFinished = onFinished
            self.adoptsCookies = adoptsCookies
        }

        /// Tells the host a navigation has settled, unless the flow is already over.
        ///
        /// - Parameters:
        ///   - webView: The web view.
        ///   - navigation: The navigation that finished.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            onFinished(webView, webView.url)
        }

        /// Decides what to do with a navigation.
        ///
        /// A CieID hand-off is cancelled and re-issued with `sourceApp` attached. A
        /// `polimi.it` navigation is kept inside this web view, because a device with the
        /// official app installed treats it as a universal link and would take the flow away
        /// mid-sign-in. Everything else is passed to the host's own decision.
        ///
        /// - Parameters:
        ///   - webView: The web view.
        ///   - navigationAction: What it is about to do.
        /// - Returns: Whether to allow it.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, !finished else { return .allow }

            // Keep polimi.it navigations inside this web view.
            //
            // On a device with the official PoliMi app installed, iOS treats
            // polimiapp.polimi.it as a universal link and hands the redirect to
            // that app part-way through login — the web view reports it as a
            // policy-change cancel and the flow simply stops. Re-issuing the
            // request programmatically avoids that: `load()` never triggers
            // universal link handling.
            //
            // Restricted to GET: re-issuing as `URLRequest(url:)` would turn a
            // form POST into a GET, and the ateneo login page submits by POST.
            if Self.shouldKeepInApp(url),
               navigationAction.request.httpMethod == "GET",
               !reissued.contains(url.absoluteString) {
                reissued.insert(url.absoluteString)
                cancelledDeliberately = true
                log.debug("Re-issuing \(url.host ?? "?", privacy: .public) navigation in-app")
                _ = await MainActor.run { webView.load(URLRequest(url: url)) }
                return .cancel
            }

            // CIE hand-off must be caught before the web view follows it. Allow
            // it even once and iOS opens CieID without `sourceApp`, and the
            // authenticated session comes back in Safari instead of here.
            if CieIDBridge.isHandoffToCieID(url) {
                log.debug("Intercepting CIE hand-off")
                cancelledDeliberately = true
                let opened = await router.openCieID(for: url)
                if !opened { onCieIDMissing() }
                return .cancel
            }

            switch decide(url) {
            case .allow:
                return .allow
            case .finish(let action):
                finished = true
                cancelledDeliberately = true
                // Cookies first: whatever the action does next runs against the
                // session this web view just established.
                if adoptsCookies { await Self.adoptCookies(from: webView) }
                await MainActor.run(body: action)
                return .cancel
            case .load(let next):
                cancelledDeliberately = true
                _ = await MainActor.run { webView.load(URLRequest(url: next)) }
                return .cancel
            }
        }

        /// Reports a navigation failure, ignoring the cancels this view asked for.
        ///
        /// That guard is what makes the CIE flow work: a deliberate cancel surfaces here as a
        /// WebKit error rather than a cancellation, and reporting it would tear the web view down
        /// before CieID could hand anything back.
        ///
        /// - Parameters:
        ///   - webView: The web view.
        ///   - navigation: The navigation that failed.
        ///   - error: Why it failed.
        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            let nsError = error as NSError

            // A cancel we asked for is not a failure. This is the single most
            // important guard in the CIE flow: without it, intercepting the
            // hand-off immediately reports an error, the host tears down the
            // web view, and the session CieID hands back has nowhere to go.
            if cancelledDeliberately {
                cancelledDeliberately = false
                log.debug("Ignoring navigation failure from our own cancel")
                return
            }

            guard !finished, !Self.isBenign(nsError) else { return }
            log.error("Login navigation failed: \(nsError.domain) \(nsError.code)")
            onError(error)
        }

        /// The host whose navigations must not escape to another app.
        ///
        /// `polimiapp.polimi.it` is claimed as a universal link by the official
        /// PoliMi app, so on a device where that app is installed iOS hands it
        /// our redirect mid-login. Deliberately narrow: every other host in the
        /// chain — the IdP, aunicalogin, the CIE provider — is left alone, so
        /// this cannot disturb the parts of the login that already work.
        static func shouldKeepInApp(_ url: URL) -> Bool {
            url.scheme == "https" && url.host == "polimiapp.polimi.it"
        }

        /// Copies the login web view's cookies into the shared store.
        ///
        /// The token exchange runs on `URLSession`, which has its own cookie
        /// jar — empty. The official app exchanges the code from inside the
        /// page that just authorized, so it carries the `polimiapp.polimi.it`
        /// session established during the flow. If the backend correlates the
        /// authorization code with that session, an exchange without it is a
        /// different request entirely, which would explain a token that
        /// authenticates but carries the wrong grant.
        ///
        /// Only `polimi.it` cookies are taken; nothing from the identity
        /// providers is worth keeping past the login.
        static func adoptCookies(from webView: WKWebView) async {
            let cookies = await webView.configuration.websiteDataStore
                .httpCookieStore.allCookies()
            let relevant = cookies.filter { $0.domain.contains("polimi.it") }
            for cookie in relevant {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            Logger(subsystem: "segrini.samuele.PoliVerse", category: "authweb")
                .info("Adopted \(relevant.count, privacy: .public) polimi.it cookies for the token exchange")
        }

        /// Exposed so the classification can be tested; it is the difference
        /// between a working CIE login and one that dies on interception.
        static func isBenignForTesting(_ error: NSError) -> Bool { isBenign(error) }

        /// Failures that mean "we stopped this on purpose" rather than
        /// "the login broke".
        private static func isBenign(_ error: NSError) -> Bool {
            switch error.domain {
            case NSURLErrorDomain:
                // -999 cancelled; -1002 unsupported scheme, which is how the
                // custom-scheme redirects surface.
                return [NSURLErrorCancelled, NSURLErrorUnsupportedURL].contains(error.code)
            case "WebKitErrorDomain":
                // 101 cannot show URL (custom scheme), 102 frame load
                // interrupted by policy change (our decisionHandler(.cancel)),
                // 204 plug-in will handle load.
                return [101, 102, 204].contains(error.code)
            default:
                return false
            }
        }
    }
}
