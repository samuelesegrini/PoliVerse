import SwiftUI
import OSLog
@preconcurrency import WebKit

/// What the host wants done with a navigation.
nonisolated enum AuthWebViewDecision {
    /// Let the web view proceed.
    case allow
    /// The host recognised this URL and dealt with it; stop navigating.
    case finish
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

    func makeCoordinator() -> Coordinator {
        Coordinator(router: router, decide: decide, onError: onError, onCieIDMissing: onCieIDMissing)
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
        if let resume = router.consume() {
            context.coordinator.resuming = true
            webView.load(URLRequest(url: resume))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let router: CieIDRouter
        private let decide: (URL) -> AuthWebViewDecision
        private let onError: (any Error) -> Void
        private let onCieIDMissing: () -> Void
        private let log = Logger(subsystem: "one.wape.PoliVerse", category: "authweb")

        weak var webView: WKWebView?
        var resuming = false
        private var finished = false

        init(
            router: CieIDRouter,
            decide: @escaping (URL) -> AuthWebViewDecision,
            onError: @escaping (any Error) -> Void,
            onCieIDMissing: @escaping () -> Void
        ) {
            self.router = router
            self.decide = decide
            self.onError = onError
            self.onCieIDMissing = onCieIDMissing
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
                let opened = await router.openCieID(for: url)
                if !opened { onCieIDMissing() }
                return .cancel
            }

            switch decide(url) {
            case .allow:
                return .allow
            case .finish:
                finished = true
                return .cancel
            case .load(let next):
                await MainActor.run { webView.load(URLRequest(url: next)) }
                return .cancel
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            let code = (error as NSError).code
            // Our own cancellations surface here, as does the unsupported-scheme
            // error from the custom redirect.
            guard !finished, code != NSURLErrorCancelled, code != NSURLErrorUnsupportedURL
            else { return }
            onError(error)
        }
    }
}
