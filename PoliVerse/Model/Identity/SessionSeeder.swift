import OSLog
@preconcurrency import WebKit

/// Uses the single sign-on session a Politecnico sign-in has just established to sign
/// WeBeep and the lecture recordings in as well, before ``LoginWebKit/endSession()``
/// ends it.
///
/// Without this each of the three runs a sign-in of its own, and since 2022 every
/// sign-in costs the student a second factor: a code from an authenticator app, an
/// SMS, or an approval in their SPID or CIE provider's app. Three in a row on a first
/// launch is the single most tiresome part of setting the app up.
///
/// Nothing is typed by or for the student here. WeBeep's sign-in is walked in a hidden
/// web view on the same store, and it gets through only because the identity provider
/// answers from the cookie it already set. A page that would need the student — the
/// Politecnico's chooser, a provider's own page — ends the walk, and that service keeps
/// its own sign-in exactly as before. The recordings are given the session's cookies,
/// which is what their own sign-in would have left in their store.
@MainActor
enum SessionSeeder {
    /// Diagnostic log for this type, under the `seeder` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "seeder")

    /// The hosts whose cookies carry the single sign-on session: aunicalogin, which every
    /// Politecnico identity provider defers to, and the Shibboleth provider in front of
    /// WeBeep and recman.
    nonisolated static let ssoHosts: Set<String> = ["aunicalogin.polimi.it", "shibidp.polimi.it"]

    /// How long the WeBeep walk may take before it is abandoned. Long enough for four
    /// redirects on a poor connection; short enough that a walk stuck on a page nobody
    /// sees does not hold a web process for long.
    static let weBeepTimeout: Duration = .seconds(20)

    /// How long a sign-in page is given to move on by itself before it counts as asking
    /// the student. An aunicalogin page answering from a valid cookie submits itself from
    /// script within a moment; the chooser waits for ever. The same grace
    /// ``RecmanBrowser`` gives.
    static let signInGrace: Duration = .seconds(3)

    /// Signs WeBeep and the recordings in on the session in `store`.
    ///
    /// WeBeep goes first, because walking its sign-in adds the Shibboleth provider's own
    /// cookies, which the recordings can then use too.
    ///
    /// - Parameters:
    ///   - store: The store the Politecnico sign-in ran on, its cookies still in place.
    ///   - deliverWeBeep: Called with the WeBeep token, or `nil` to leave WeBeep alone —
    ///     when it is already connected, for instance.
    static func seed(
        from store: WKWebsiteDataStore,
        weBeep deliverWeBeep: ((WeBeepAuth.MoodleToken) -> Void)?
    ) async {
        if let deliverWeBeep {
            if let token = await weBeepToken(on: store) {
                log.notice("WeBeep signed in on the Politecnico session")
                deliverWeBeep(token)
            } else {
                log.notice("WeBeep could not be signed in on the Politecnico session; it keeps its own sign-in")
            }
        }
        let copied = await seedRecordings(from: store)
        log.notice("Gave the recordings \(copied, privacy: .public) single sign-on cookies")
    }

    // MARK: - Recordings

    /// Whether a cookie's domain is one of ``ssoHosts``.
    ///
    /// - Parameter domain: The cookie's domain, with or without the leading dot.
    /// - Returns: `true` for a single sign-on cookie.
    nonisolated static func isSSODomain(_ domain: String) -> Bool {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return ssoHosts.contains(host.lowercased())
    }

    /// Copies the single sign-on cookies into ``RecordingsWebKit/dataStore``.
    ///
    /// They are what the recordings' own sign-in would have left there, and they go when
    /// ``RecordingsWebKit/endSession()`` does, on sign-out. Nothing is written to the
    /// Keychain here: ``RecordingsWebKit/saveSession()`` keeps a session only once recman
    /// has accepted it.
    ///
    /// - Parameter store: The store to copy from.
    /// - Returns: How many cookies were copied.
    @discardableResult
    static func seedRecordings(from store: WKWebsiteDataStore) async -> Int {
        let cookies = await store.httpCookieStore.allCookies().filter { isSSODomain($0.domain) }
        let target = RecordingsWebKit.dataStore.httpCookieStore
        for cookie in cookies {
            await target.setCookie(cookie)
        }
        return cookies.count
    }

    // MARK: - WeBeep

    /// What the WeBeep walk does with one navigation.
    nonisolated enum WeBeepStep: Equatable {
        /// The token redirect: read it and stop.
        case token
        /// Moodle's dashboard: a session exists, so ask `launch.php` for the token.
        case launch
        /// A page someone would have to act on. Stop; WeBeep keeps its own sign-in.
        case needsStudent
        /// A page of the Politecnico's sign-in: either a hop that submits itself on the
        /// cookie, or the chooser. Follow it, and stop if it settles and stays.
        case signInHop
        /// A redirect on the way. Follow it.
        case follow
    }

    /// Decides what the WeBeep walk does with a navigation.
    ///
    /// - Parameters:
    ///   - url: Where the hidden web view is about to go.
    ///   - launched: Whether `launch.php` has already been asked for the token.
    /// - Returns: The step.
    nonisolated static func weBeepStep(for url: URL, launched: Bool) -> WeBeepStep {
        guard let scheme = url.scheme?.lowercased() else { return .follow }
        if WeBeepAuth.acceptedSchemes.contains(scheme) { return .token }
        if scheme == "about" { return .follow }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else {
            return .needsStudent
        }

        if !launched, WeBeepAuth.isLoggedInPage(url) { return .launch }

        // Every step of a sign-in that goes through on its cookie stays on the
        // Politecnico's own hosts. Leaving them means a SPID or CIE provider's
        // page, which wants the student.
        guard host == "polimi.it" || host.hasSuffix(".polimi.it") else { return .needsStudent }

        // aunicalogin and the Shibboleth provider either answer from the cookie,
        // often through a page that submits itself, or show the chooser. Which
        // one only shows once the page has had a moment.
        if ssoHosts.contains(host) { return .signInHop }

        // Moodle's own login page: `launch.php` sends there when Moodle has no
        // session after all.
        if host == "webeep.polimi.it", url.path == "/login/index.php" { return .needsStudent }

        return .follow
    }

    /// Walks WeBeep's sign-in on the session in `store` and returns the token.
    ///
    /// - Parameter store: The store holding the single sign-on session.
    /// - Returns: The token, or `nil` when the walk reached a page that needs the
    ///   student, failed, or ran out of time.
    static func weBeepToken(on store: WKWebsiteDataStore) async -> WeBeepAuth.MoodleToken? {
        let walk = WeBeepWalk(store: store)
        return await walk.run(timeout: weBeepTimeout)
    }
}

/// One hidden walk through WeBeep's sign-in, following ``SessionSeeder/weBeepStep(for:launched:)``.
private final class WeBeepWalk: NSObject, WKNavigationDelegate {
    /// Diagnostic log, under the same category as ``SessionSeeder``.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "seeder")
    /// The web view doing the walk. Never on screen.
    private let webView: WKWebView
    /// Fresh per walk, so the token's signature is bound to this one.
    private let passport = WeBeepAuth.newPassport()
    /// Whether `launch.php` has been asked for the token.
    private var launched = false
    /// Counts navigations, so a sign-in page can be seen to have stayed put.
    private var navigations = 0
    /// Resumed exactly once, by ``finish(_:reason:)``.
    private var continuation: CheckedContinuation<WeBeepAuth.MoodleToken?, Never>?

    /// Creates the walk on `store`.
    ///
    /// - Parameter store: The store holding the single sign-on session.
    init(store: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// Starts at WeBeep's Shibboleth entry and waits for the token or for a reason to stop.
    ///
    /// - Parameter timeout: How long to wait.
    /// - Returns: The token, or `nil`.
    func run(timeout: Duration) async -> WeBeepAuth.MoodleToken? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: WeBeepAuth.loginURL))
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(nil, reason: "timed out")
            }
        }
    }

    /// Ends the walk, once.
    ///
    /// - Parameters:
    ///   - token: What to hand back.
    ///   - reason: Why, for the log.
    private func finish(_ token: WeBeepAuth.MoodleToken?, reason: String) {
        guard let continuation else { return }
        self.continuation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        log.debug("WeBeep walk ended: \(reason, privacy: .public)")
        continuation.resume(returning: token)
    }

    /// Follows, launches, reads or stops, per ``SessionSeeder/weBeepStep(for:launched:)``.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard continuation != nil, let url = navigationAction.request.url else { return .cancel }
        navigations += 1
        switch SessionSeeder.weBeepStep(for: url, launched: launched) {
        case .token:
            do {
                finish(try WeBeepAuth.token(from: url, passport: passport), reason: "token")
            } catch {
                finish(nil, reason: "unreadable token redirect")
            }
            return .cancel
        case .launch:
            launched = true
            webView.load(URLRequest(url: WeBeepAuth.launchURL(passport: passport)))
            return .cancel
        case .needsStudent:
            // Host only: the path and query can carry session identifiers.
            finish(nil, reason: "needs the student at \(url.host ?? "?")")
            return .cancel
        case .follow, .signInHop:
            return .allow
        }
    }

    /// Gives a settled sign-in page ``SessionSeeder/signInGrace`` to move on, and stops if
    /// it does not: it is waiting for the student.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil, let url = webView.url,
              SessionSeeder.weBeepStep(for: url, launched: launched) == .signInHop else { return }
        let seen = navigations
        Task { [weak self] in
            try? await Task.sleep(for: SessionSeeder.signInGrace)
            guard let self, self.navigations == seen else { return }
            self.finish(nil, reason: "sign-in page stayed at \(url.host ?? "?")")
        }
    }

    /// Stops on a real failure, ignoring the cancels the walk asked for itself.
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        let nsError = error as NSError
        // 102 is a navigation cancelled by policy — ours, when `launch.php` is
        // loaded in place of the dashboard — and -999 a load replaced by another.
        if nsError.domain == "WebKitErrorDomain", [101, 102].contains(nsError.code) { return }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        finish(nil, reason: "failed \(nsError.domain) \(nsError.code)")
    }

    /// Stops on a failure after the page began to load.
    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        finish(nil, reason: "failed \(nsError.domain) \(nsError.code)")
    }
}
