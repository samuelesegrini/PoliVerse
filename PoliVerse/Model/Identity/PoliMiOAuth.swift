import Foundation

/// The Politecnico's OAuth endpoints and the requests that drive them.
///
/// One leg: with no session cookie present, the identity provider prompts for
/// credentials itself and then redirects to ``redirectURI`` with an authorisation
/// code, which ``tokenExchangeRequest(authCode:)`` exchanges for a token pair.
///
/// The client id and scope list come from ``ServiceDirectory/OAuthParams`` rather
/// than from the constants here, which are fallbacks only.
nonisolated enum PoliMiOAuth {
    /// Registered client for the official Politecnico app. A fallback; the live value
    /// comes from `/jaf/oauth/params`.
    static let clientID = "1057407812"

    /// Where the identity provider redirects on success, with `?code=` appended.
    static let redirectURI = "https://polimiapp.polimi.it/polimi_app/app"

    /// The public logout-link request, which answers a `targetURL` on `aunicalogin`
    /// that ends the single sign-on session rather than only the app's.
    ///
    /// This matters for scope changes: with a live single sign-on session the identity
    /// provider can answer a new authorisation request by re-issuing a code against the
    /// existing grant, ignoring a widened scope — so signing in again would return the
    /// same narrow token and the affected services would keep refusing it.
    ///
    /// - Parameter serviceID: The service to log out of, sent as `logout_service_id`.
    /// - Returns: The unauthenticated request.
    static func logoutLinkRequest(serviceID: String = "2428") -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/public/linklogout",
            query: [
                .init(name: "lang", value: PoliMiLanguage.current.lowercased),
                .init(name: "logout_service_id", value: serviceID),
            ],
            authenticated: false
        )
    }

    /// The answer to ``logoutLinkRequest(serviceID:)``.
    nonisolated struct LogoutLink: Decodable, Sendable {
        /// The page to open in order to end the single sign-on session.
        let targetURL: String?
    }

    /// Server-side invalidation of the current token, as the official app performs on
    /// sign-out.
    static var revokeRequest: APIRequest {
        APIRequest(host: .app, path: "/jaf/oauth/revoke", method: "POST")
    }

    /// Which authorisation is being asked for.
    ///
    /// Made explicit because the two differ in four parameters at once — endpoint,
    /// matricola, access token and scope — and getting one wrong silently produces the
    /// other flow.
    nonisolated enum AuthorizationFlow: Sendable, Equatable {
        /// A full sign-in, requesting the whole scope list.
        ///
        /// `hintMatricola` asks the identity provider to bind the new grant to a particular
        /// enrolment. It is only a hint; the reliable lever is setting the favourite career
        /// beforehand.
        case login(hintMatricola: String? = nil)
        /// Moves an existing grant to another enrolment without a fresh sign-in.
        ///
        /// - Important: the Politecnico's `/careerChange` endpoint currently errors for at
        ///   least some accounts, reproducibly in the official app as well, so the app
        ///   offers a fresh sign-in instead. Kept because the flow is correct and the
        ///   endpoint may recover.
        case careerChange(matricola: String, accessToken: String)

        /// The enrolment this flow names — the hint for a sign-in, the target for a career
        /// change.
        var matricola: String? {
            switch self {
            case .login(let hint): hint
            case .careerChange(let matricola, _): matricola
            }
        }
    }

    /// Builds the authorisation URL for a flow.
    ///
    /// Mirrors the official client's request, including the keys it sends empty, and
    /// percent-encodes the query by hand as `URLSearchParams` does — `queryItems` would
    /// leave `:` and `/` unescaped in `redirect_uri`.
    ///
    /// A career change sends the access token and an empty scope, since it moves an
    /// existing grant; a sign-in sends the full scope list and no token, or the new
    /// token comes back with no authority.
    ///
    /// - Parameters:
    ///   - params: The OAuth configuration to build from.
    ///   - state: The `state` parameter, a fresh UUID by default.
    ///   - flow: Which authorisation is being asked for.
    /// - Returns: The URL to load in the sign-in web view.
    static func authorizationURL(
        params: ServiceDirectory.OAuthParams = .fallback,
        state: String = UUID().uuidString,
        flow: AuthorizationFlow = .login()
    ) -> URL {
        let isCareerChange: Bool
        if case .careerChange = flow { isCareerChange = true } else { isCareerChange = false }
        let endpoint = isCareerChange
            ? params.careerChangeEndpoint
            : params.authorizationEndpoint
        var components = URLComponents(
            url: endpoint ?? URL(string: "https://oauthidp.polimi.it/oauthidp/oauth2/auth")!,
            resolvingAgainstBaseURL: false
        )!
        // Mirrors the official app's authorize request exactly, including the
        // keys it leaves empty — it builds them with `URLSearchParams`, so
        // every key is present regardless.
        //
        // `al_id_srv` is sent empty, as the official app does when opened
        // directly. An earlier guess that a non-empty value was required is
        // wrong: the IdP drops the parameter entirely, and the redirect it
        // returns is byte-identical either way.
        //
        // Encoded by hand rather than through `queryItems`, which leaves `:`
        // and `/` unescaped — so `redirect_uri` went over the wire raw while
        // the official app, using `URLSearchParams`, sends it fully escaped
        // with `+` for spaces. Matching that byte-for-byte removes one more
        // way our authorize request can differ from the one that works.
        let pairs: [(String, String)] = [
            ("client_id", params.clientId),
            ("redirect_uri", redirectURI),
            ("access_type", params.accessType ?? "offline"),
            ("response_type", params.responseType ?? "code"),
            ("state", state),
            ("matricola", flow.matricola ?? ""),
            ("al_pj_matricola", flow.matricola ?? ""),
            // The token is the evidence of who is asking, and only a career
            // change needs it — a login has nothing to prove yet.
            ("access_token", {
                if case .careerChange(_, let token) = flow { return token }
                return ""
            }()),
            // `scope: n ? "" : t.scope` in the bundle. A career change moves
            // an existing grant rather than requesting a new one; a login,
            // including one hinting at a matricola, must ask for the full
            // list or the new token comes back with no authority.
            ("scope", isCareerChange ? "" : params.scope),
            ("al_id_srv", ""),
            ("al_id_srv_chiamante", ""),
        ]
        components.percentEncodedQuery = pairs
            .map { "\($0.0)=\(formURLEncoded($0.1))" }
            .joined(separator: "&")
        return components.url!
    }

    /// Encodes a value as `application/x-www-form-urlencoded`, the way
    /// `URLSearchParams` does: spaces become `+`, and everything outside the unreserved
    /// set is percent-escaped.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The encoded value, or the input unchanged if it cannot be encoded.
    static func formURLEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+")
            ?? value
    }

    /// Reads the authorisation code out of a redirect.
    ///
    /// The query is parsed rather than the prefix stripped, so appended or reordered
    /// parameters do not break it.
    ///
    /// - Parameter url: The navigation the web view is following.
    /// - Returns: The code, or `nil` when the URL is not the redirect or carries none.
    static func authCode(from url: URL) -> String? {
        guard url.absoluteString.hasPrefix(redirectURI) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// Exchanges an authorisation code for a token pair. No client secret is involved.
    ///
    /// - Parameter authCode: The code from ``authCode(from:)``.
    /// - Returns: The unauthenticated request.
    static func tokenExchangeRequest(authCode: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/oauth/token/get/\(authCode)",
            authenticated: false
        )
    }

    /// Exchanges a refresh token for a fresh token pair.
    ///
    /// - Note: the refresh token travels in the path rather than in a header or body,
    ///   which is the endpoint's own design and means it can reach server access logs.
    ///
    /// - Parameter refreshToken: The refresh token to present.
    /// - Returns: The unauthenticated request.
    static func refreshRequest(refreshToken: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/oauth/token/refresh/\(refreshToken)",
            authenticated: false
        )
    }
}
