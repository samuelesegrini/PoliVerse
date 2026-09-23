import OSLog
import UIKit
@preconcurrency import WebKit

/// Finds where a Webex recording streams, by letting Webex's own page ask.
///
/// The playback page signs in to Webex through the Politecnico's single sign-on —
/// the session ``RecordingsWebKit`` keeps — and then calls
/// `/webappng/api/v1/recordings/<id>/stream` with a ticket it reads from its own
/// markup. Rather than rebuild that request and its headers, a script injected at
/// document start watches the page's `fetch` and `XMLHttpRequest` and hands over the
/// answer, the way ``LoginWebKit/credentialObserver(key:)`` hands over a credential.
///
/// The page is never seen, but it is in the window, behind the app's own views:
/// Webex's sign-in steps submit themselves only in a page WebKit counts as
/// visible, and one outside any window stalls on `idbroker…/doSSO.jsp`. Content
/// rules keep it from fetching the video itself, images and fonts, and the chat
/// and participant list — other people's data, which the app has no use for.
@MainActor
final class WebexPlayback: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// What looking up a recording came to.
    enum Outcome: Equatable {
        /// Webex answered.
        case stream(WebexStream)
        /// The page stopped on a sign-in: the session has lapsed.
        case signInNeeded
        /// Anything else, with a sentence for the log.
        case failed(String)
    }

    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// The page doing the asking.
    private let webView: WKWebView
    /// Receives the outcome of the look-up in progress.
    private var waiter: CheckedContinuation<Outcome, Never>?
    /// Counts navigations, so a delayed check can tell whether the page moved on.
    private var navigations = 0
    /// Counts look-ups, so a timeout left over from an earlier one cannot end the
    /// current one.
    private var lookup = 0
    /// The email to give Webex's sign-in when it asks, in this look-up.
    private var email: String?
    /// Whether the email has been given in this look-up, so a refusal is not
    /// answered with the same email forever.
    private var gaveEmail = false

    /// Name of the message handler the injected script posts to.
    private static let messageName = "poliverseWebexStream"

    /// Watches the page's own requests and posts the `/stream` answer.
    ///
    /// The original methods run first and their results are returned unchanged.
    private static let observer = """
    (function () {
      var post = function (text) {
        try { window.webkit.messageHandlers.\(messageName).postMessage(String(text)); } catch (e) {}
      };
      var isStream = function (url) { return /\\/webappng\\/api\\/v1\\/recordings\\/[^\\/?]+\\/stream/.test(String(url)); };
      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function (input, init) {
          var url = typeof input === 'string' ? input : (input && input.url);
          return originalFetch.apply(this, arguments).then(function (response) {
            if (isStream(url) && response.ok) { response.clone().text().then(post).catch(function () {}); }
            return response;
          });
        };
      }
      var open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__poliverseStream = isStream(url);
        return open.apply(this, arguments);
      };
      var send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        if (this.__poliverseStream) {
          this.addEventListener('load', function () {
            if (this.status !== 200) { return; }
            try { post(typeof this.response === 'string' ? this.response : JSON.stringify(this.response)); } catch (e) {}
          });
        }
        return send.apply(this, arguments);
      };
    })();
    """

    /// Keeps the hidden page from loading what the app does not need: the video
    /// (served from `nfg*.webex.com`), the chat and the participants, images, fonts
    /// and media.
    private static let rules = """
    [
      {"trigger": {"url-filter": "^https?://nfg[^/]*\\\\.webex\\\\.com/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "chat\\\\.json"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "/participants"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": ".*", "if-domain": ["*webex.com"], "resource-type": ["image", "font", "media"]},
       "action": {"type": "block"}}
    ]
    """

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = RecordingsWebKit.dataStore
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.observer, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        // Held weakly by a proxy, so the controller does not keep this object alive.
        configuration.userContentController.add(WeakMessageHandler(self), name: Self.messageName)
        Task { @MainActor [webView] in
            if let rules = await Self.compiledRules() {
                webView.configuration.userContentController.add(rules)
            }
        }
    }

    /// The compiled content rules, compiled once and kept by WebKit.
    private static func compiledRules() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        let identifier = "segrini.samuele.PoliVerse.webex-rules"
        if let existing = try? await store.contentRuleList(forIdentifier: identifier) { return existing }
        return try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
    }

    // MARK: - Looking up

    /// Opens a recording's Webex page and waits for its `/stream` answer.
    ///
    /// Webex keeps its sign-in per page rather than in a cookie, so every look-up
    /// passes through its identity broker, which asks for the account's email before
    /// handing over to the Politecnico. The email is typed into that form here, as
    /// autofill would; the rest of the sign-in runs on the kept session.
    ///
    /// - Parameters:
    ///   - address: The recording's Webex address, `ldr.php?RCID=…` or its playback
    ///     page.
    ///   - email: The student's Webex email, to give the broker when it asks.
    /// - Returns: The stream, or why it could not be had.
    func stream(at address: URL, email: String?) async -> Outcome {
        self.email = email
        gaveEmail = false
        lookup += 1
        let current = lookup
        attachToWindow()
        return await withCheckedContinuation { continuation in
            waiter = continuation
            webView.load(URLRequest(url: address))
            Task {
                try? await Task.sleep(for: .seconds(40))
                guard self.lookup == current else { return }
                self.finish(.failed("timeout at \(self.webView.url?.host ?? "?")\(self.webView.url?.path ?? "")"))
            }
        }
    }

    /// Hands the outcome over, once, and stops the page.
    private func finish(_ outcome: Outcome) {
        guard let waiter else { return }
        self.waiter = nil
        if case .failed(let reason) = outcome { log.error("Webex look-up failed: \(reason, privacy: .public)") }
        webView.stopLoading()
        // Nothing of the page is needed any more; an empty page stops its scripts.
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
        waiter.resume(returning: outcome)
    }

    /// Puts the page in the key window, behind everything, where no one sees it or
    /// touches it but WebKit runs it as a visible page.
    private func attachToWindow() {
        guard webView.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.keyWindow
        guard let window else { return }
        webView.frame = window.bounds
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        window.insertSubview(webView, at: 0)
    }

    // MARK: - Messages

    /// Receives the `/stream` answer the injected script posts.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName, let text = message.body as? String,
              let data = text.data(using: .utf8) else { return }
        do {
            let stream = try JSONDecoder().decode(WebexStream.self, from: data)
            if stream.hlsURL == nil { log.error("Webex stream answer without an HLS address") }
            finish(.stream(stream))
        } catch {
            finish(.failed("stream answer unreadable: \(error.localizedDescription)"))
        }
    }

    // MARK: - Navigation

    /// Counts navigations, for the sign-in check.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigations += 1
        return .allow
    }

    /// A sign-in page with somewhere to type, still there after a few seconds, has
    /// asked for the student.
    ///
    /// Webex's and the Politecnico's sign-in steps mostly submit themselves when the
    /// session holds; those have no email or password field and are left to run.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard waiter != nil, let url = webView.url, Self.isSignIn(url) else { return }
        let seen = navigations
        Task {
            // The broker's email form: answered at once when the email is known.
            if let email, !gaveEmail, await giveEmail(email) {
                gaveEmail = true
                log.info("Webex asked for the email; given")
                return
            }
            try? await Task.sleep(for: .seconds(4))
            guard self.navigations == seen, self.waiter != nil else { return }
            let asks = (try? await webView.evaluateJavaScript(Self.asksForCredentials) as? Bool) ?? false
            guard asks else {
                self.log.info("Webex waiting on \(url.host ?? "?", privacy: .public)\(url.path, privacy: .public), nothing to fill in")
                return
            }
            if self.navigations == seen, self.waiter != nil {
                self.log.info("Webex stopped on a sign-in: \(url.host ?? "?", privacy: .public)\(url.path, privacy: .public)")
                self.finish(.signInNeeded)
            }
        }
    }

    /// A navigation that failed before any page came back ends the look-up.
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled, code != 102 else { return }
        finish(.failed("navigation \((error as NSError).domain) \(code)"))
    }

    /// Gives the email to Webex's identity broker and sends it on.
    ///
    /// The broker's page (`idbroker…/doSSO.jsp`) keeps its Sign In button disabled
    /// until its own validation, run on typing, sets `nameValidated`; a value set by
    /// script and a click on the disabled button do nothing. So this sets the field,
    /// marks it validated and calls the page's own `processForm()`, which hashes the
    /// email and posts its hidden `GlobalEmailLookupForm` to `/idb/globalLogin`. On a
    /// page without those functions, the hidden form is filled and posted directly.
    ///
    /// - Parameter email: The email.
    /// - Returns: Whether the page had the email field to fill.
    private func giveEmail(_ email: String) async -> Bool {
        let body = """
        var field = document.getElementById('IDToken1')
          || document.querySelector('input[type=email], input[name=email]');
        if (!field) { return false; }
        field.value = email;
        field.dispatchEvent(new Event('input', { bubbles: true }));
        if (typeof window.processForm === 'function') {
          window.nameValidated = true;
          window.processForm();
          return true;
        }
        var form = document.getElementById('GlobalEmailLookupForm');
        if (form) {
          var hidden = form.querySelector('input[name=email]');
          if (hidden) { hidden.value = email; }
          form.submit();
          return true;
        }
        var button = field.form && field.form.querySelector('button[type=submit], input[type=submit]');
        if (button) { button.disabled = false; button.click(); }
        return true;
        """
        do {
            let filled = try await webView.callAsyncJavaScript(
                body, arguments: ["email": email], contentWorld: .page) as? Bool
            return filled ?? false
        } catch {
            // The page's own message, which names what it tripped on; the email is
            // an argument, never part of the source, so it is not in the message.
            let info = (error as NSError).userInfo
            let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            log.error("Giving Webex the email failed: \(message, privacy: .public)")
            return false
        }
    }

    /// Whether the page shows a field for an email, a username or a password.
    private static let asksForCredentials = """
    (function () {
      var fields = document.querySelectorAll('input[type=email], input[type=password], input[name=email], input[name=IDToken1], input[name=login], input[name=username]');
      for (var i = 0; i < fields.length; i++) {
        var box = fields[i].getBoundingClientRect();
        if (box.width > 0 && box.height > 0) { return true; }
      }
      return false;
    })();
    """

    /// Whether a page is a sign-in step: Webex's identity broker, or the
    /// Politecnico's.
    private static func isSignIn(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.hasPrefix("idbroker")
            || ["aunicalogin.polimi.it", "shibidp.polimi.it", "cie.polimi.it"].contains(host)
            || (host.hasSuffix("webex.com") && url.path.hasSuffix("/login"))
    }
}

/// Forwards script messages to a handler held weakly, since a user content
/// controller keeps its handlers alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    /// The real handler.
    private weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
