import OSLog
@preconcurrency import WebKit

/// The WebKit configuration the sign-in runs on.
///
/// The sign-in has to run the Politecnico's own Servizi Online single-page app,
/// which is around 13.7 MB of JavaScript and CSS, because a token minted by the app
/// directly is refused by the data services while the one that app mints is
/// accepted. See ``PoliMiAppLoginWebView``.
///
/// ## What this type provides
///
/// - ``dataStore``: a persistent store under a fixed identifier, so those 13.7 MB
///   are cached between sign-ins. ``endSession()`` then removes cookies and web
///   storage while keeping the cache, so a Shibboleth session still cannot outlive
///   the flow.
/// - ``contentRules()``: blocks images, media and fonts on the Politecnico's app
///   host only.
/// - ``credentialObserver(key:)``: reports the credential in the same turn the page
///   writes it, rather than polling for it.
/// - ``prewarm(_:)``: loads the page while the student is still on the sign-in
///   screen.
@MainActor
enum LoginWebKit {
    /// Diagnostic log for this type, under the `loginweb` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "loginweb")

    /// A persistent website data store of the app's own, separate from anything else
    /// WebKit holds.
    ///
    /// The identifier is fixed, since a new one each launch would mean an empty cache
    /// each launch.
    static let dataStore: WKWebsiteDataStore = {
        let identifier = UUID(uuidString: "7F1C2A64-9E3B-4D58-A0E7-1B6C5D9F2A83")!
        return WKWebsiteDataStore(forIdentifier: identifier)
    }()

    /// Removes cookies, session storage and local storage from ``dataStore``, leaving
    /// the disk cache intact.
    ///
    /// Called when a sign-in finishes and when the student signs out.
    static func endSession() async {
        await dataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies,
                      WKWebsiteDataTypeSessionStorage,
                      WKWebsiteDataTypeLocalStorage],
            modifiedSince: .distantPast)
        log.info("Login cookies cleared; cache kept")
    }

    // MARK: - Blocking what the login does not need

    /// Content rules blocking images, media and fonts on `polimiapp.polimi.it`.
    ///
    /// Scoped to that host deliberately: the identity providers' pages are ones the
    /// student reads and taps, and their buttons are often images, so blocking there
    /// would make the sign-in unusable. The page behind it is never read — it exists to
    /// run its JavaScript and hand back a credential.
    private static let ruleSource = """
    [
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": ["polimiapp.polimi.it"],
          "resource-type": ["image", "media", "font"]
        },
        "action": { "type": "block" }
      }
    ]
    """

    /// Identifier the compiled rule list is stored under.
    private static let ruleIdentifier = "segrini.samuele.PoliVerse.login-rules"

    /// The compiled content rules, compiling them on first use and letting WebKit keep
    /// them between launches.
    ///
    /// - Returns: The rule list, or `nil` when it cannot be compiled — in which case
    ///   the sign-in is slower rather than broken.
    static func contentRules() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        if let existing = try? await store.contentRuleList(forIdentifier: ruleIdentifier) {
            return existing
        }
        do {
            return try await store.compileContentRuleList(
                forIdentifier: ruleIdentifier, encodedContentRuleList: ruleSource)
        } catch {
            // Not fatal: without the rules the login is slower, not broken.
            log.error("Could not compile login content rules: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Being told rather than asking

    /// Name of the WebKit message handler ``credentialObserver(key:)`` posts to.
    static let messageName = "poliverseCredentials"

    /// A script that reports the credential the moment the page writes it.
    ///
    /// Wraps `Storage.prototype.setItem` and posts the value to ``messageName`` when
    /// the named key is written, then also posts any value already present — which
    /// happens when the page is restored rather than loaded. The original method is
    /// called first and its result returned unchanged, so the page cannot tell.
    ///
    /// Injected at document start, so the hook is in place before the page's own code
    /// runs.
    ///
    /// - Parameter key: The session-storage key to watch.
    /// - Returns: The user script to add to the configuration.
    static func credentialObserver(key: String) -> WKUserScript {
        let source = """
        (function () {
          const target = '\(key)';
          const original = Storage.prototype.setItem;
          Storage.prototype.setItem = function (name, value) {
            const result = original.apply(this, arguments);
            if (name === target) {
              try {
                window.webkit.messageHandlers.\(messageName).postMessage(String(value));
              } catch (ignored) {}
            }
            return result;
          };
          // Already there — a credential written before this script ran, which
          // happens when the page is restored rather than loaded.
          try {
            const existing = window.sessionStorage.getItem(target);
            if (existing) {
              window.webkit.messageHandlers.\(messageName).postMessage(String(existing));
            }
          } catch (ignored) {}
        })();
        """
        return WKUserScript(
            source: source,
            // At document start, so the hook is in place before any of the
            // SPA's own code runs.
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
    }

    // MARK: - Warming

    /// The web view loading the page ahead of time, released after ninety seconds.
    private static var warmed: WKWebView?

    /// Loads the sign-in page while the student is still on the sign-in screen, so the
    /// web view appears with the page already up.
    ///
    /// Does nothing when a warm view is already held. The view is released after ninety
    /// seconds rather than held for the life of the process.
    ///
    /// - Parameter url: The page to load.
    static func prewarm(_ url: URL) {
        guard warmed == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        warmed = webView
        log.info("Prewarming the login page")

        // Released after a while: holding a second web process indefinitely
        // to save a load nobody asked for is a bad trade.
        Task {
            try? await Task.sleep(for: .seconds(90))
            warmed = nil
        }
    }
}
