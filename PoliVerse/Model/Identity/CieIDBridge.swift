import Foundation
import UIKit

/// Keeps “Entra con CIE” inside PoliVerse rather than losing the session to Safari.
///
/// When the identity provider navigates to the CIE server, iOS hands the
/// navigation to the CieID app. CieID does not know who called it, so after the
/// NFC read and the PIN it returns the authenticated URL to the default browser —
/// and the session cookie lands in Safari rather than in the app's `WKWebView`.
///
/// CieID accepts a `sourceApp` query parameter naming the scheme to return to, so
/// the flow is: recognise the outbound navigation with ``isHandoffToCieID(_:)``,
/// cancel it, re-open it with ``handoffURL(for:sourceApp:)``, and recover the
/// returned https URL with ``returnURL(from:)`` to load into the same web view.
/// ``CieIDRouter`` drives that sequence.
///
/// - Important: the outbound navigation must be cancelled before the web view
///   follows it. Allowing it through even once hands off without `sourceApp`, and
///   the return goes to the browser.
nonisolated enum CieIDBridge {
    /// The URL scheme CieID is told to return to.
    ///
    /// The bundle identifier, as the CieID SDK asks integrators to use, and distinct
    /// from the `poliverse` scheme used for the WeBeep token — so neither handler can
    /// misread the other's payload.
    static let returnScheme = "segrini.samuele.PoliVerse"

    /// CieID's own scheme. Upper case as the SDK writes it; schemes are
    /// case-insensitive.
    static let cieIDScheme = "CIEID"

    /// CieID's App Store page, offered when the app is not installed.
    static let appStoreURL = URL(string: "https://apps.apple.com/it/app/cieid/id1504644677")!

    /// Host fragment identifying the CIE identity provider on the way out, truncated
    /// exactly as the SDK's own constant is.
    private static let idpOutboundHost = "ios.idserver.servizicie.interno.go"

    /// Host the identity provider sends the student back through once authenticated.
    private static let idpReturnHost = "idserver.servizicie.interno.gov.it"

    // MARK: - Outbound

    /// Whether a navigation is the hand-off to the CieID app.
    ///
    /// Matches an identity-provider URL carrying `nextUrl`, or any path containing
    /// `livello1` or `livello2`, which are the CIE assurance levels.
    ///
    /// - Parameter url: The navigation the web view is about to follow.
    /// - Returns: `true` when the navigation must be cancelled and handed off.
    static func isHandoffToCieID(_ url: URL) -> Bool {
        let string = url.absoluteString
        if string.contains(idpOutboundHost) && string.contains("nextUrl") { return true }
        let path = url.pathComponents
        return path.contains("livello1") || path.contains("livello2")
    }

    /// Rewrites an identity-provider URL into the `CIEID://…&sourceApp=…` form.
    ///
    /// Built by concatenation rather than with `URLComponents`: the whole https URL
    /// sits where the host would go, so composing it through `URLComponents`
    /// percent-escapes the payload and CieID rejects it.
    ///
    /// - Parameters:
    ///   - url: The navigation to hand off.
    ///   - sourceApp: The scheme CieID should return to.
    /// - Returns: The hand-off URL, or `nil` when it cannot be formed.
    static func handoffURL(for url: URL, sourceApp: String = returnScheme) -> URL? {
        let separator = url.query == nil ? "?" : "&"
        let withSource = url.absoluteString + separator + "sourceApp=" + sourceApp
        return URL(string: "\(cieIDScheme)://\(withSource)")
    }

    // MARK: - Inbound

    /// Recovers the https URL CieID handed back.
    ///
    /// The payload arrives as `<scheme>://https://idserver…`, and CieID sometimes
    /// writes `https//` with a single slash, which is repaired before parsing.
    ///
    /// - Parameter url: The incoming URL.
    /// - Returns: The https URL to load, or `nil` when the scheme is not
    ///   ``returnScheme`` or no usable URL can be recovered.
    static func returnURL(from url: URL) -> URL? {
        guard url.scheme?.caseInsensitiveCompare(returnScheme) == .orderedSame else { return nil }

        var string = url.absoluteString.replacingOccurrences(of: "https//", with: "https://")
        guard let range = string.range(of: "https://") else { return nil }
        string = String(string[range.lowerBound...])

        guard let recovered = URL(string: string), recovered.host != nil else { return nil }
        return recovered
    }

    /// Whether a recovered URL came back through the CIE identity provider. Used for
    /// logging only; the flow does not depend on it.
    ///
    /// - Parameter url: The recovered URL.
    /// - Returns: `true` when it names the identity provider's host.
    static func isIdPReturn(_ url: URL) -> Bool {
        url.absoluteString.contains(idpReturnHost)
    }

    /// The failure CieID reported on the return URL, if any.
    ///
    /// - Parameter url: The recovered URL.
    /// - Returns: The value of `cieid_error_message`, or `nil` when the return
    ///   succeeded.
    static func errorMessage(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "cieid_error_message" }?
            .value
    }
}
