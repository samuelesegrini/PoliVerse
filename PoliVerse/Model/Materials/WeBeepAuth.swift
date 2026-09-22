import Foundation
import CryptoKit

/// Obtaining a Moodle web-service token for WeBeep.
///
/// WeBeep is a stock Moodle behind the Politecnico's Shibboleth identity provider, and
/// Moodle ships a supported handshake for exactly that case — `admin/tool/mobile/launch.php`,
/// the one the official Moodle app uses on SSO-only sites.
///
/// ## The flow
///
/// 1. Load ``loginURL`` so the student sees the university sign-in they recognise.
/// 2. Once ``loggedInURL`` is reached, load ``launchURL(passport:)``.
/// 3. Moodle redirects to `<scheme>://token=<base64>`, which the web view intercepts
///    and ``token(from:passport:verifySignature:)`` decodes.
///
/// The payload is `signature:::token[:::privatetoken]`, and the signature is the MD5
/// of the site URL and the passport.
nonisolated enum WeBeepAuth {
    /// WeBeep's base URL, which the token signature is computed over.
    static let siteURL = "https://webeep.polimi.it"

    /// The scheme Moodle is asked to redirect to.
    static let urlScheme = "poliverse"

    /// The schemes the redirect interceptor recognises.
    ///
    /// `launch.php` lets a site override the requested scheme at redirect time, after
    /// sign-in, so the requested one cannot be relied on. Accepting both is safe here: the
    /// redirect is cancelled inside the app's own `WKWebView` before iOS sees it, so this
    /// never competes with the real Moodle app for a system-wide scheme.
    static let acceptedSchemes: Set<String> = ["poliverse", "moodlemobile"]

    /// Where the Shibboleth sign-in begins.
    ///
    /// Loaded before `launch.php`, so the student sees the university sign-in they
    /// recognise.
    static var loginURL: URL {
        URL(string: "\(siteURL)/auth/shibboleth/index.php")!
    }

    /// The page reached once a Moodle session exists, which is the signal to hand off to
    /// `launch.php`.
    static var loggedInURL: URL {
        URL(string: "\(siteURL)/my/")!
    }

    /// The token-launch URL.
    ///
    /// - Parameter passport: A nonce echoed back inside the signed payload, which is what
    ///   makes the signature check meaningful.
    /// - Returns: The URL to load once signed in.
    static func launchURL(passport: String) -> URL {
        var components = URLComponents(string: "\(siteURL)/admin/tool/mobile/launch.php")!
        components.queryItems = [
            .init(name: "service", value: "moodle_mobile_app"),
            .init(name: "passport", value: passport),
            .init(name: "urlscheme", value: urlScheme),
        ]
        return components.url!
    }

    /// A fresh passport nonce.
    ///
    /// - Returns: A random number as a string.
    static func newPassport() -> String {
        String(UInt32.random(in: 1_000_000...UInt32.max))
    }

    /// What can go wrong reading the token redirect.
    enum TokenError: LocalizedError {
        /// The URL is not one of ``acceptedSchemes``, or carries no `token=`.
        case notATokenRedirect
        /// The payload is not base64, not text, or does not carry a signature and a token.
        case malformedPayload
        /// The payload's signature does not match the passport that was sent.
        case signatureMismatch

        /// The localised sentence shown to the student.
        var errorDescription: String? {
            switch self {
            case .notATokenRedirect: "Risposta di WeBeep non riconosciuta."
            case .malformedPayload: "WeBeep ha restituito un token illeggibile."
            case .signatureMismatch: "La firma del token WeBeep non corrisponde."
            }
        }
    }

    /// A web-service token for WeBeep.
    struct MoodleToken: Sendable, Equatable {
        /// The web-service token every `mod_*` and `core_*` call carries.
        let token: String
        /// Moodle's private token, used for auto-login links. Not needed for web-service
        /// calls, and kept only because it arrives in the same payload. Absent unless the
        /// student has just signed in.
        let privateToken: String?
    }

    /// Parses a `<scheme>://token=<base64>` redirect into a usable token.
    ///
    /// The redirect is not a conventional query string, so it is read from the raw string
    /// rather than through `URLComponents`, and its base64 is padded if the URL dropped
    /// the padding. A two-part payload is normal: the private token is omitted unless the
    /// student has just signed in.
    ///
    /// - Parameters:
    ///   - url: The intercepted redirect.
    ///   - passport: The nonce that was sent, which the signature is checked against.
    ///   - verifySignature: Whether to check the signature. Defence in depth against a
    ///     hostile page, since the redirect is intercepted inside the app's own web view
    ///     rather than through a system-wide scheme handler.
    /// - Returns: The token.
    /// - Throws: ``TokenError``.
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

    /// Restores base64 padding a URL may have dropped.
    ///
    /// - Parameter value: The encoded payload.
    /// - Returns: The payload padded to a multiple of four characters.
    private static func padded(_ value: String) -> String {
        let remainder = value.count % 4
        return remainder == 0 ? value : value + String(repeating: "=", count: 4 - remainder)
    }

    /// The MD5 of a string, hex-encoded.
    ///
    /// MD5 only because Moodle chose it for this signature; it is not used as a security
    /// primitive here.
    ///
    /// - Parameter value: The string to hash.
    /// - Returns: The lower-case hex digest.
    static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
    }
}
