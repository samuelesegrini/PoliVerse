import Foundation
import UIKit

/// Keeps "Entra con CIE" inside PoliVerse instead of losing it to Safari.
///
/// ## The problem
///
/// When the ateneo login page offers CIE, the page itself navigates to the
/// CIE identity provider. Left alone, iOS hands that off to the CieID app —
/// but CieID has no idea who called it, so when the user finishes with NFC and
/// PIN it returns the authenticated URL to the **default browser**. The session
/// cookie lands in Safari's jar, our `WKWebView` never sees it, and the login
/// is gone.
///
/// ## The fix
///
/// The CieID app takes a `sourceApp` query parameter naming the URL scheme to
/// come back to. The official SDK (`italia/cieid-ios-sdk`,
/// `CieIDWKWebViewController.redirectFlow`) does this:
///
/// ```swift
/// let string = urlCaught.absoluteString + "&sourceApp=\(urlSchemeString)"
/// let finalURL = URL(string: "CIEID://" + string)
/// UIApplication.shared.open(finalURL)
/// ```
///
/// So we must intercept the IdP navigation **before** the web view follows it,
/// cancel it, and re-open it ourselves with `sourceApp` attached. CieID then
/// returns to `<scheme>://https://idserver.servizicie.interno.gov.it/…`, which
/// we strip back to a plain https URL and load into the *same* web view — the
/// one holding the session.
///
/// Getting the interception right is the whole trick: if the navigation is
/// allowed to proceed even once, the hand-off happens without `sourceApp` and
/// the return goes to Safari.
nonisolated enum CieIDBridge {
    /// The scheme CieID is told to return to.
    ///
    /// The SDK's README asks integrators to use the bundle identifier as the
    /// scheme, so this deliberately differs from the plain `poliverse` scheme
    /// used for the Moodle token — the two return payloads are unrelated and
    /// keeping them apart means neither handler can mis-parse the other.
    static let returnScheme = "one.wape.PoliVerse"

    /// CieID's own scheme. Upper case as the SDK writes it; schemes are
    /// case-insensitive, but matching the SDK avoids surprises.
    static let cieIDScheme = "CIEID"

    static let appStoreURL = URL(string: "https://apps.apple.com/it/app/cieid/id1504644677")!

    /// Host fragment identifying the CIE identity provider.
    ///
    /// Truncated exactly as the SDK's `IDP_URL_COMPONENT` is — it matches
    /// `ios.idserver.servizicie.interno.gov.it` as a prefix.
    private static let idpOutboundHost = "ios.idserver.servizicie.interno.go"

    /// Host the IdP sends the user back through once authenticated.
    private static let idpReturnHost = "idserver.servizicie.interno.gov.it"

    // MARK: - Outbound

    /// True when this navigation is the hand-off to the CieID app.
    ///
    /// Mirrors the SDK's condition: an IdP URL carrying `nextUrl`, or a path
    /// containing `livello1` / `livello2` (CIE assurance levels).
    static func isHandoffToCieID(_ url: URL) -> Bool {
        let string = url.absoluteString
        if string.contains(idpOutboundHost) && string.contains("nextUrl") { return true }
        let path = url.pathComponents
        return path.contains("livello1") || path.contains("livello2")
    }

    /// Rewrites an IdP URL into the `CIEID://…&sourceApp=…` form.
    ///
    /// - Note: built by string concatenation rather than `URLComponents`.
    ///   `CIEID://https://host/...` is not a legal URL in the eyes of
    ///   `URLComponents` — the whole https URL sits where the host should be —
    ///   so composing it "properly" percent-escapes the payload and CieID
    ///   rejects it. The SDK concatenates for the same reason.
    static func handoffURL(for url: URL, sourceApp: String = returnScheme) -> URL? {
        let separator = url.query == nil ? "?" : "&"
        let withSource = url.absoluteString + separator + "sourceApp=" + sourceApp
        return URL(string: "\(cieIDScheme)://\(withSource)")
    }

    // MARK: - Inbound

    /// Extracts the https URL CieID handed back.
    ///
    /// The payload arrives as `<scheme>://https://idserver…`. CieID sometimes
    /// mangles it to `https//` with a single slash — the official SDK patches
    /// exactly that before parsing, so we do too.
    static func returnURL(from url: URL) -> URL? {
        guard url.scheme?.caseInsensitiveCompare(returnScheme) == .orderedSame else { return nil }

        var string = url.absoluteString.replacingOccurrences(of: "https//", with: "https://")
        guard let range = string.range(of: "https://") else { return nil }
        string = String(string[range.lowerBound...])

        guard let recovered = URL(string: string), recovered.host != nil else { return nil }
        return recovered
    }

    /// Whether a returned URL looks like it came back through the CIE IdP.
    /// Used only for logging — the flow does not depend on it.
    static func isIdPReturn(_ url: URL) -> Bool {
        url.absoluteString.contains(idpReturnHost)
    }

    /// Error message CieID reports back on the URL, if any.
    static func errorMessage(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "cieid_error_message" }?
            .value
    }
}
