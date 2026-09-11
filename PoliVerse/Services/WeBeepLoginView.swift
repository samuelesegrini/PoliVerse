import SwiftUI
@preconcurrency import WebKit

/// Drives the WeBeep login and captures the Moodle token.
///
/// Three navigations matter:
/// 1. `auth/shibboleth/index.php` — the user authenticates at the ateneo IdP.
/// 2. `/my/` — the session now exists; hand off to `launch.php`.
/// 3. `poliverse://token=…` — the token, intercepted before it can escape to
///    the system URL handler.
struct WeBeepLoginView: UIViewRepresentable {
    let onToken: (WeBeepAuth.MoodleToken) -> Void
    let onError: (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Non-persistent: the Shibboleth session cookie should not outlive the
        // login. The Moodle token we keep instead lives in the Keychain.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: WeBeepAuth.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onToken: (WeBeepAuth.MoodleToken) -> Void
        private let onError: (any Error) -> Void

        /// Fresh per login attempt, so the signature check means something.
        private let passport = WeBeepAuth.newPassport()
        private var handedOffToLaunch = false
        private var finished = false

        init(
            onToken: @escaping (WeBeepAuth.MoodleToken) -> Void,
            onError: @escaping (any Error) -> Void
        ) {
            self.onToken = onToken
            self.onError = onError
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, !finished else { return .allow }

            // The token redirect. Cancel it so iOS never tries to open the
            // scheme system-wide.
            if let scheme = url.scheme, WeBeepAuth.acceptedSchemes.contains(scheme) {
                finished = true
                do {
                    onToken(try WeBeepAuth.token(from: url, passport: passport))
                } catch {
                    onError(error)
                }
                return .cancel
            }

            // Logged in. Swap to the token handshake.
            if !handedOffToLaunch, isLoggedInPage(url) {
                handedOffToLaunch = true
                let launch = WeBeepAuth.launchURL(passport: passport)
                await MainActor.run { webView.load(URLRequest(url: launch)) }
                return .cancel
            }

            return .allow
        }

        /// Moodle lands on `/my/` or `/my/index.php`, sometimes with a query.
        private func isLoggedInPage(_ url: URL) -> Bool {
            guard url.host == "webeep.polimi.it" else { return false }
            let path = url.path
            return path == "/my/" || path == "/my" || path == "/my/index.php"
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            // Cancelling the redirects above surfaces here; that is our doing.
            let code = (error as NSError).code
            guard !finished, code != NSURLErrorCancelled,
                  code != NSURLErrorUnsupportedURL else { return }
            onError(error)
        }
    }
}
