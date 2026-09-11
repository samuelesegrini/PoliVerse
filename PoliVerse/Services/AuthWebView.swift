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
    /// deciding stays free of side effects; an earlier version fired it twice
    /// simply by asking the same question twice.
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
    let startURL: URL
    let router: CieIDRouter
    /// Called for every navigation so the host can spot its own completion URL.
    let decide: (URL) -> AuthWebViewDecision
    let onError: (any Error) -> Void
    /// Called when the IdP hand-off fails because CieID is not installed.
    var onCieIDMissing: () -> Void = {}
    /// Called after each navigation settles, so a host can sequence steps or
    /// inspect the page.
    var onFinished: (WKWebView, URL?) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(router: router, decide: decide, onError: onError,
                    onCieIDMissing: onCieIDMissing, onFinished: onFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Non-persistent, so a Shibboleth session never outlives the login and
        // "log out" genuinely logs out.
        //
        // The trade-off is real: the CieID detour backgrounds PoliVerse for as
        // long as the user takes to tap their card and enter a PIN, and if iOS
        // reclaims the app in that window the in-memory cookies go with it and
        // the login must be restarted. Persisting them would survive that but
        // would leave an ateneo session on disk indefinitely.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: startURL))
        return webView
    }

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

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let router: CieIDRouter
        private let decide: (URL) -> AuthWebViewDecision
        private let onError: (any Error) -> Void
        private let onCieIDMissing: () -> Void
        private let onFinished: (WKWebView, URL?) -> Void
        let log = Logger(subsystem: "one.wape.PoliVerse", category: "authweb")

        weak var webView: WKWebView?
        var resuming = false
        private var finished = false
        /// Set whenever we cancel a navigation on purpose.
        ///
        /// Cancelling surfaces in `didFailProvisionalNavigation` as
        /// `WebKitErrorDomain` 102 — not as `NSURLErrorCancelled` — so without
        /// this the CIE hand-off reported itself as a login failure and the
        /// host dismissed the web view. CieID would then return to nothing.
        private var cancelledDeliberately = false

        init(
            router: CieIDRouter,
            decide: @escaping (URL) -> AuthWebViewDecision,
            onError: @escaping (any Error) -> Void,
            onCieIDMissing: @escaping () -> Void,
            onFinished: @escaping (WKWebView, URL?) -> Void
        ) {
            self.router = router
            self.decide = decide
            self.onError = onError
            self.onCieIDMissing = onCieIDMissing
            self.onFinished = onFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            onFinished(webView, webView.url)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, !finished else { return .allow }

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
                await Self.adoptCookies(from: webView)
                await MainActor.run(body: action)
                return .cancel
            case .load(let next):
                cancelledDeliberately = true
                await MainActor.run { webView.load(URLRequest(url: next)) }
                return .cancel
            }
        }

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
            Logger(subsystem: "one.wape.PoliVerse", category: "authweb")
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
