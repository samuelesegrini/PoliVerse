import Foundation

/// Recognises the moments a sign-in page hands the student to another app — their SPID
/// provider's, as a rule — so that the web view can let them go and still be there when
/// they come back.
///
/// SPID level 2 puts the second factor on the provider, and on a phone the quickest
/// one is an approval in the provider's own app. PosteID's page, for one, offers "Hai
/// l'App PosteID? Accedi più rapidamente", and the button runs
///
/// ```js
/// window.location.replace("https://appregistry-posteid.mobile.poste.it/jod-login-schema/btcs/pid/access/v1/?tranId=…")
/// ```
///
/// a universal link the PosteID app claims, while the page polls for the approval. A
/// `WKWebView` does not reliably hand a script-driven navigation to the app; it may load
/// the link's fallback page in its own frame instead, and the poll is lost. So the
/// navigation is recognised with ``route(for:)``, cancelled, and opened by the app with
/// `universalLinksOnly`, which leaves the page in place and still polling.
///
/// A provider page can also open its app through a scheme of its own.
/// ``isExternalScheme(_:)`` recognises those, which a web view cannot load and would
/// otherwise drop without a word.
///
/// CieID is not here: it has to be told where to return, which ``CieIDBridge`` does.
nonisolated enum IdentityAppHandoff {
    /// One app a sign-in page can hand over to through a universal link.
    nonisolated struct Route: Equatable, Sendable {
        /// The app's name, for the line shown while the student is away.
        let appName: String
        /// The host the universal link is on.
        let host: String
        /// The paths the app claims on that host, as prefixes.
        let pathPrefixes: [String]
    }

    /// The universal-link hand-offs known to appear in the sign-in.
    ///
    /// PosteID's paths are the ones its `apple-app-site-association` on the host lists,
    /// read on 2026-10-22. The QR-code paths are left out: a QR code is for signing in on
    /// another device.
    static let routes: [Route] = [
        Route(
            appName: "PosteID",
            host: "appregistry-posteid.mobile.poste.it",
            pathPrefixes: ["/jod-login-schema/btcs/pid/access/", "/jod-securelogin-schema/btcs/pid/access/"]
        ),
    ]

    /// The hand-off a navigation is, if it is one.
    ///
    /// - Parameter url: The navigation the web view is about to follow.
    /// - Returns: The route, or `nil` for an ordinary navigation.
    static func route(for url: URL) -> Route? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        return routes.first { route in
            route.host == host && route.pathPrefixes.contains { url.path.hasPrefix($0) }
        }
    }

    /// Schemes a web view loads itself.
    private static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "javascript", "file"]

    /// Whether a navigation is to a scheme only another app can open.
    ///
    /// The schemes the sign-in flows catch for themselves are not external: the WeBeep
    /// token redirect, and CieID's return to this app.
    ///
    /// - Parameter url: The navigation the web view is about to follow.
    /// - Returns: `true` when the system should open it.
    static func isExternalScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if webSchemes.contains(scheme) { return false }
        if WeBeepAuth.acceptedSchemes.contains(scheme) { return false }
        if scheme == CieIDBridge.returnScheme.lowercased() { return false }
        if scheme == CieIDBridge.cieIDScheme.lowercased() { return false }
        return true
    }
}
