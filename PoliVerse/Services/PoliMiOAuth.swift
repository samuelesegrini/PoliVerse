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
    static func authorizationURL(
        params: ServiceDirectory.OAuthParams = .fallback
    ) -> URL {
        var components = URLComponents(
            url: params.authorizationEndpoint ?? URL(string: "https://oauthidp.polimi.it/oauthidp/oauth2/auth")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "client_id", value: params.clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: params.scope),
            .init(name: "access_type", value: params.accessType ?? "offline"),
            .init(name: "response_type", value: params.responseType ?? "code"),
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
