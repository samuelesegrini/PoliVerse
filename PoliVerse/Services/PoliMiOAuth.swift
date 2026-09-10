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
    /// Registered client for the official PoliMi app, which is what the IdP
    /// will accept a redirect to `polimiapp.polimi.it` from.
    static let clientID = "1057407812"

    /// The URL the IdP redirects to on success, with `?code=` appended.
    static let redirectURI = "https://polimiapp.polimi.it/polimi_app/app"

    /// Every scope the official app asks for. Trimming this is tempting but the
    /// IdP rejects scopes the client is not registered for, so it is safer to
    /// mirror the official set than to guess a minimal one.
    static let scopes = [
        "openid", "polimi_app", "aule", "policard", "incarichi", "orario",
        "account", "webmail", "faqappmobile", "rubrica", "richass", "guasti",
        "prenotazione", "code", "carriera", "alumni", "webeep", "teamwork",
        "esami", "rich_sing_occup", "incarichidocente", "react_iae",
        "compila_quest", "multichance_richieste_ausili", "maps", "pianostudente",
    ]

    static var authorizationURL: URL {
        var components = URLComponents(string: "https://oauthidp.polimi.it/oauthidp/oauth2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "access_type", value: "offline"),
            .init(name: "response_type", value: "code"),
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

    /// `GET /rest/jaf/oauth/token/get/{authcode}` — exchange, no client secret.
    static func tokenExchangeRequest(authCode: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/rest/jaf/oauth/token/get/\(authCode)",
            authenticated: false
        )
    }

    /// `GET /rest/jaf/oauth/token/refresh/{refreshToken}`.
    ///
    /// Note the refresh token travels in the *path*, not a header or body — an
    /// upstream design choice worth knowing about, since it means the token can
    /// end up in server access logs.
    static func refreshRequest(refreshToken: String) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/rest/jaf/oauth/token/refresh/\(refreshToken)",
            authenticated: false
        )
    }
}
