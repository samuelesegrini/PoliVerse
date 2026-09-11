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

    static func authorizationURL(
        params: ServiceDirectory.OAuthParams = .fallback,
        state: String = UUID().uuidString
    ) -> URL {
        var components = URLComponents(
            url: params.authorizationEndpoint ?? URL(string: "https://oauthidp.polimi.it/oauthidp/oauth2/auth")!,
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
        components.queryItems = [
            .init(name: "client_id", value: params.clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "access_type", value: params.accessType ?? "offline"),
            .init(name: "response_type", value: params.responseType ?? "code"),
            .init(name: "state", value: state),
            .init(name: "matricola", value: ""),
            .init(name: "al_pj_matricola", value: ""),
            .init(name: "access_token", value: ""),
            .init(name: "scope", value: params.scope),
            .init(name: "al_id_srv", value: ""),
            .init(name: "al_id_srv_chiamante", value: ""),
        ]
        return components.url!
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
