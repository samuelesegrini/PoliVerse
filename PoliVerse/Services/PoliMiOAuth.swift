import Foundation

/// The Politecnico OAuth endpoints, transcribed from the flow PoliFemo drives
/// in `src/pages/Login.tsx`.
///
/// PoliFemo runs **two** legs: Microsoft SSO to mint a PoliNetwork token, then
/// the PoliMi IdP to mint a PoliMi token. The first leg exists only to serve
/// PoliNetwork's own features (news, room search, groups) — nothing PoliVerse
/// needs. We run the second leg alone: with no session cookie present, the IdP
/// prompts for credentials itself and then cascade-redirects with the authcode.
///
/// It also avoids PoliFemo's most brittle step — reading the token out of
/// `document.body.innerText` with injected JavaScript.
nonisolated enum PoliMiOAuth {
    /// Registered client for the official PoliMi app. Kept only as a fallback
    /// — the live value comes from `/jaf/oauth/params`.
    static let clientID = "1057407812"

    /// The URL the IdP redirects to on success, with `?code=` appended.
    static let redirectURI = "https://polimiapp.polimi.it/polimi_app/app"

    /// Builds the authorization URL from the server's own OAuth config.
    ///
    /// Hardcoding the scope list is what broke the agenda: a token minted
    /// without the `agenda` scope reaches the right endpoint and is refused
    /// with 401. Asking the Politecnico what to request means a scope change
    /// upstream costs a fetch, not a broken feature.
    /// Public logout endpoint. Returns a `targetURL` on `aunicalogin` that
    /// ends the **SSO session**, not just the app's own.
    ///
    /// This matters more than it looks. With a live `aunicalogin` session the
    /// IdP can answer a new authorize request by re-issuing a code against the
    /// *existing* grant, ignoring the widened `scope` — so a user who "logs in
    /// again" gets the old narrow token back and the services keep returning
    /// "Scope OAuth non valido". Ending the SSO session is precisely what the
    /// server means by "effettuare logout/login".
    static func logoutLinkRequest(serviceID: String = "2428") -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/public/linklogout",
            query: [
                .init(name: "lang", value: "it"),
                .init(name: "logout_service_id", value: serviceID),
            ],
            authenticated: false
        )
    }

    nonisolated struct LogoutLink: Decodable, Sendable {
        let targetURL: String?
    }

    /// Server-side invalidation of the current token, as the official app does
    /// on logout.
    static var revokeRequest: APIRequest {
        APIRequest(host: .app, path: "/jaf/oauth/revoke", method: "POST")
    }

    /// Which authorisation is being asked for.
    ///
    /// Made explicit because the two differ in four parameters at once —
    /// endpoint, matricola, access token and scope — and getting one wrong
    /// silently produces the other flow. A login asking for no scopes, or a
    /// career change asking for all of them, both fail in ways that look
    /// like something else.
    nonisolated enum AuthorizationFlow: Sendable, Equatable {
        /// A full login. `hintMatricola` asks the IdP to bind the new grant
        /// to a particular enrolment; it is only a hint, and the reliable
        /// lever is `PUT /v1/careers/favorite/{matricola}` set beforehand.
        case login(hintMatricola: String? = nil)
        /// Moves an existing grant to another enrolment without a new login.
        ///
        /// - Important: the Politecnico's own `/careerChange` currently errors
        ///   for at least some accounts — reproduced in the official app — so
        ///   the app offers re-login instead. Kept because the flow is correct
        ///   and the endpoint may recover.
        case careerChange(matricola: String, accessToken: String)

        var matricola: String? {
            switch self {
            case .login(let hint): hint
            case .careerChange(let matricola, _): matricola
            }
        }
    }

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

    /// `application/x-www-form-urlencoded`, as `URLSearchParams` produces it:
    /// spaces become `+`, everything outside the unreserved set is escaped.
    static func formURLEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+")
            ?? value
    }

    /// Pulls the authcode out of a redirect.
    ///
    /// PoliFemo did `url.replace(polimiTargetUrl, "")`, which breaks the moment
    /// the IdP appends `&state=` or reorders parameters. Parsing the query is
    /// the same amount of code and does not.
    static func authCode(from url: URL) -> String? {
        guard url.absoluteString.hasPrefix(redirectURI) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// `GET /jaf/oauth/token/get/{authcode}` on the app base — no client secret.
    static func tokenExchangeRequest(authCode: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/oauth/token/get/\(authCode)",
            authenticated: false
        )
    }

    /// `GET /jaf/oauth/token/refresh/{refreshToken}` on the app base.
    ///
    /// Note the refresh token travels in the *path*, not a header or body — an
    /// upstream design choice worth knowing about, since it means the token can
    /// end up in server access logs.
    static func refreshRequest(refreshToken: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/oauth/token/refresh/\(refreshToken)",
            authenticated: false
        )
    }
}
