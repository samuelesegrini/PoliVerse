import Foundation
import CryptoKit

/// Obtaining a Moodle web-service token for WeBeep.
///
/// ## Why this is not scraping
///
/// WeBeep is a stock Moodle behind the Politecnico's Shibboleth IdP
/// (`shibidp.polimi.it`). Moodle ships a supported handshake for exactly this
/// case — `admin/tool/mobile/launch.php`, the one the official Moodle app uses
/// on SSO-only sites. Confirmed live against WeBeep: requesting
///
/// ```
/// GET /admin/tool/mobile/launch.php?service=moodle_mobile_app&passport=…&urlscheme=poliverse
/// ```
///
/// returns `303 See Other` and sets a `tool_mobile_launch` cookie containing
/// our own scheme:
///
/// ```json
/// {"service":"moodle_mobile_app","passport":"…","urlscheme":"poliverse","confirmed":0,"oauthsso":0}
/// ```
///
/// After the user authenticates, Moodle redirects to
/// `poliverse://token=<base64>` where the payload decodes to
/// `signature:::token:::privatetoken`.
///
/// ## Prior art
///
/// Two independent implementations agree on this:
/// - `toto04/webeep-sync` (Electron, maintained 2026) uses this exact flow.
/// - `matteovisotto/myPoliFile` (Swift, on the App Store) uses an older
///   variant — after SSO it loads
///   `login/token.php?username=<codicePersona>@polimi.it&password=&service=moodle_mobile_app`
///   and scrapes the JSON out of the page body. That works, but needs the
///   person code and depends on empty-password login being permitted, so the
///   launch.php route is the better one.
nonisolated enum WeBeepAuth {
    static let siteURL = "https://webeep.polimi.it"

    /// The scheme we ask Moodle to redirect to.
    static let urlScheme = "poliverse"

    /// Schemes the interceptor must recognise.
    ///
    /// `launch.php` ends with:
    ///
    /// ```php
    /// $forcedurlscheme = get_config('tool_mobile', 'forcedurlscheme');
    /// if (!empty($forcedurlscheme)) { $urlscheme = $forcedurlscheme; }
    /// ```
    ///
    /// so a site can override whatever we asked for. The override is applied at
    /// redirect time — after login — which is why probing the launch endpoint
    /// beforehand cannot reveal it: the `tool_mobile_launch` cookie happily
    /// echoes back our scheme either way. `webeep-sync` registers a handler for
    /// `moodlemobile` specifically, which suggests WeBeep does force it.
    ///
    /// Accepting both is safe here: the redirect is cancelled inside our own
    /// `WKWebView` before iOS sees it, so this never competes with the real
    /// Moodle app for a system-wide scheme.
    static let acceptedSchemes: Set<String> = ["poliverse", "moodlemobile"]

    /// Entry point for the Shibboleth login. Hitting this first (rather than
    /// launch.php) means the user sees the normal ateneo login they recognise.
    static var loginURL: URL {
        URL(string: "\(siteURL)/auth/shibboleth/index.php")!
    }

    /// Reached once the session exists; the signal to hand off to launch.php.
    static var loggedInURL: URL {
        URL(string: "\(siteURL)/my/")!
    }

    /// Builds the token-launch URL.
    ///
    /// - Parameter passport: a random nonce echoed back inside the signed
    ///   payload. `webeep-sync` hardcodes `12345`; generating one per attempt
    ///   costs nothing and makes the signature check meaningful.
    static func launchURL(passport: String) -> URL {
        var components = URLComponents(string: "\(siteURL)/admin/tool/mobile/launch.php")!
        components.queryItems = [
            .init(name: "service", value: "moodle_mobile_app"),
            .init(name: "passport", value: passport),
            .init(name: "urlscheme", value: urlScheme),
        ]
        return components.url!
    }

    static func newPassport() -> String {
        String(UInt32.random(in: 1_000_000...UInt32.max))
    }

    enum TokenError: LocalizedError {
        case notATokenRedirect
        case malformedPayload
        case signatureMismatch

        var errorDescription: String? {
            switch self {
            case .notATokenRedirect: "Risposta di WeBeep non riconosciuta."
            case .malformedPayload: "WeBeep ha restituito un token illeggibile."
            case .signatureMismatch: "La firma del token WeBeep non corrisponde."
            }
        }
    }

    struct MoodleToken: Sendable, Equatable {
        let token: String
        /// Moodle's "private token", used for auto-login links. Not needed for
        /// web-service calls; kept because it arrives in the same payload.
        let privateToken: String?
    }

    /// Parses `poliverse://token=<base64>` into a usable token.
    ///
    /// The payload is `siteid:::token[:::privatetoken]`, confirmed against
    /// `admin/tool/mobile/launch.php` in Moodle 4.5:
    ///
    /// ```php
    /// $siteid = md5($CFG->wwwroot . $passport);
    /// $apptoken = $siteid . ':::' . $token->token;
    /// if ($privatetoken and is_https() and !$siteadmin) { $apptoken .= ':::' . $privatetoken; }
    /// $location = "$urlscheme://token=" . base64_encode($apptoken);
    /// ```
    ///
    /// The private token is omitted unless the user just logged in, so a
    /// two-part payload is normal and not an error.
    ///
    /// - Parameter verifySignature: when the payload's signature does not match,
    ///   the call throws. The redirect is intercepted inside our own `WKWebView`
    ///   rather than through a system-wide URL scheme handler, so a hostile app
    ///   cannot inject one — this is defence in depth against a hostile *page*,
    ///   not the only thing standing between us and a forged token.
    static func token(
        from url: URL,
        passport: String,
        verifySignature: Bool = true
    ) throws -> MoodleToken {
        guard let scheme = url.scheme, acceptedSchemes.contains(scheme) else {
            throw TokenError.notATokenRedirect
        }

        // The redirect is `poliverse://token=<base64>` — not a conventional
        // query string, so `URLComponents` sees it as the host or path
        // depending on form. Work from the raw string.
        let raw = url.absoluteString
        guard let range = raw.range(of: "token=") else { throw TokenError.notATokenRedirect }
        let encoded = String(raw[range.upperBound...])
            .removingPercentEncoding ?? String(raw[range.upperBound...])

        guard
            let data = Data(base64Encoded: padded(encoded)),
            let decoded = String(data: data, encoding: .utf8)
        else { throw TokenError.malformedPayload }

        let parts = decoded.components(separatedBy: ":::")
        guard parts.count >= 2, !parts[1].isEmpty else { throw TokenError.malformedPayload }

        if verifySignature {
            let expected = md5Hex(siteURL + passport)
            guard parts[0] == expected else { throw TokenError.signatureMismatch }
        }

        return MoodleToken(
            token: parts[1],
            privateToken: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        )
    }

    /// Base64 in a URL may arrive without its padding.
    private static func padded(_ value: String) -> String {
        let remainder = value.count % 4
        return remainder == 0 ? value : value + String(repeating: "=", count: 4 - remainder)
    }

    /// MD5 only because Moodle chose it for this signature; it is not being
    /// used as a security primitive on our side.
    static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
    }
}
