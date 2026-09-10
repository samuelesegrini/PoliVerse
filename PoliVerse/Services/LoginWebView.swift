import SwiftUI
@preconcurrency import WebKit

/// Hosts the IdP login page and reports the authcode when the redirect fires.
///
/// `ASWebAuthenticationSession` would be the idiomatic choice, but it can only
/// catch a callback on a custom scheme or an https domain the app owns via
/// Associated Domains. The redirect here lands on `polimiapp.polimi.it`, which
/// is not ours, so intercepting navigation in a `WKWebView` is the only option
/// short of PoliMi registering a scheme for us.
struct LoginWebView: UIViewRepresentable {
    let url: URL
    /// Called once, on the first redirect carrying a `code`.
    let onCode: (String) -> Void
    let onError: (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A non-persistent store means the login page never leaves a session
        // cookie behind on disk, so "log out" is genuinely a log out.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCode: (String) -> Void
        private let onError: (any Error) -> Void
        private var finished = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (any Error) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        /// The async form of the policy callback. The completion-handler
        /// overload takes a `@MainActor` closure in the current SDK, and a
        /// signature that does not match exactly is silently never called —
        /// the compiler only warns that it "nearly matches".
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            if let code = PoliMiOAuth.authCode(from: url), !finished {
                finished = true
                onCode(code)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            guard !finished else { return }
            onError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            // Cancelling the redirect above surfaces here as NSURLErrorCancelled;
            // that is our own doing, not a failure.
            guard !finished, (error as NSError).code != NSURLErrorCancelled else { return }
            onError(error)
        }
    }
}
