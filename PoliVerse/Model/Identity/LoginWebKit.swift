import OSLog
@preconcurrency import WebKit

/// The WebKit setup the login runs on.
///
/// ## What was slow, measured
///
/// The official Servizi Online SPA is **13.7 MB** on every login — 8.27 MB of
/// JavaScript and 5.43 MB of CSS — and the app has to run it, because a token
/// this app mints itself is rejected by the data services while the one the
/// SPA mints is accepted (see ``PoliMiAppLoginWebView``).
///
/// Both files are cacheable: `cache-control: private` with an `ETag` and a
/// `Last-Modified`, so a second load should be two 304s and nothing else. The
/// web view was using a **non-persistent** data store, which throws the cache
/// away with the view — so every single login downloaded all 13.7 MB again.
///
/// ## The trade, stated
///
/// The non-persistent store was not an accident: it guaranteed that a
/// Shibboleth session could never outlive the login. That property is worth
/// keeping, and it does not require throwing away the cache with it. This uses
/// a persistent store scoped to its own identifier and deletes **cookies**
/// when the flow ends — so the session dies exactly as before, and the 13.7 MB
/// survives.
@MainActor
enum LoginWebKit {
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "loginweb")

    /// A store of this app's own, separate from anything else WebKit holds.
    ///
    /// The identifier is fixed, because a new one each launch would be a new
    /// empty cache each launch — which is what we are trying to stop.
    static let dataStore: WKWebsiteDataStore = {
        let identifier = UUID(uuidString: "7F1C2A64-9E3B-4D58-A0E7-1B6C5D9F2A83")!
        return WKWebsiteDataStore(forIdentifier: identifier)
    }()

    /// Removes the session while keeping the cache.
    ///
    /// Cookies only — not `WKWebsiteDataTypeDiskCache`, which is the whole
    /// point. Called when a login finishes and when the user signs out.
    static func endSession() async {
        await dataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies,
                      WKWebsiteDataTypeSessionStorage,
                      WKWebsiteDataTypeLocalStorage],
            modifiedSince: .distantPast)
        log.info("Login cookies cleared; cache kept")
    }

    // MARK: - Blocking what the login does not need

    /// Blocks images, media and fonts **on the Politecnico's own app host**.
    ///
    /// Scoped to that host deliberately. The identity providers — CIE, SPID,
    /// aunicalogin — are pages the user actually reads and taps, and their
    /// buttons are often images; blocking there would make the login
    /// unusable. The SPA behind it is a page nobody reads: it exists to run
    /// its JavaScript and hand back a credential.
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

    private static let ruleIdentifier = "segrini.samuele.PoliVerse.login-rules"

    /// Compiled once and kept by WebKit between launches.
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

    static let messageName = "poliverseCredentials"

    /// Reports the credential the moment the SPA writes it.
    ///
    /// Replaces a polling loop that woke every 400 ms up to twenty-five times:
    /// in the worst case the app sat there for ten seconds after the login had
    /// already succeeded. Hooking `setItem` means the message arrives in the
    /// same turn the SPA stores the value.
    ///
    /// The original method is called first and its result returned unchanged,
    /// so the page cannot tell the difference.
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

    private static var warmed: WKWebView?

    /// Loads the SPA while the user is still looking at the login screen.
    ///
    /// The expensive part is parsing 8 MB of JavaScript, and it can happen
    /// during the seconds before anyone taps anything. On a warm cache this
    /// makes the web view appear with the page already up.
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
