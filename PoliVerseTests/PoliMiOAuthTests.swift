import Foundation
import Testing
@testable import PoliVerse

/// The authorize request, which has to match the official app byte for byte.
///
/// Every rule pinned here was learned from a failure that looked like
/// something else: a token minted without the `agenda` scope that reaches the
/// right endpoint and is refused with 401; a `redirect_uri` sent raw because
/// `queryItems` leaves `:` and `/` unescaped; a career change that asks for
/// scopes and comes back as a login. None of them shows up as a bad request —
/// they show up as a feature that does not work.
@Suite("OAuth del Politecnico")
struct PoliMiOAuthTests {
    private let params = ServiceDirectory.OAuthParams(
        oauthServer: "https://oauthidp.polimi.it/oauthidp/oauth2",
        clientId: "1057407812",
        scope: "agenda carriera webeep",
        responseType: "code",
        accessType: "offline")

    /// The query as it goes over the wire: still encoded, still in order.
    private func rawQuery(_ url: URL) -> [(String, String)] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return (components?.percentEncodedQuery ?? "").split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
        }
    }

    private func value(_ name: String, in url: URL) -> String? {
        rawQuery(url).first { $0.0 == name }?.1
    }

    // MARK: Codifica

    /// `URLSearchParams`, which the official app builds its query with, is
    /// `application/x-www-form-urlencoded`: spaces become `+` and everything
    /// outside the unreserved set is escaped.
    @Test("Gli spazi diventano più, il resto è codificato come nel form")
    func formEncoding() {
        #expect(PoliMiOAuth.formURLEncoded("agenda carriera") == "agenda+carriera")
        #expect(PoliMiOAuth.formURLEncoded("https://polimiapp.polimi.it/polimi_app/app")
                == "https%3A%2F%2Fpolimiapp.polimi.it%2Fpolimi_app%2Fapp")
        #expect(PoliMiOAuth.formURLEncoded("a*b-c.d_e") == "a*b-c.d_e")
        #expect(PoliMiOAuth.formURLEncoded("") == "")
    }

    // MARK: Login

    @Test("Un login va all’endpoint di autorizzazione")
    func loginEndpoint() {
        let url = PoliMiOAuth.authorizationURL(params: params)
        #expect(url.absoluteString.hasPrefix("https://oauthidp.polimi.it/oauthidp/oauth2/auth?"))
    }

    /// The official app builds its query with `URLSearchParams`, so every key
    /// is present even when empty. Missing keys are a difference from the
    /// request that is known to work.
    @Test("Tutte le chiavi ci sono, anche quelle vuote")
    func everyKeyIsPresent() {
        let names = rawQuery(PoliMiOAuth.authorizationURL(params: params)).map(\.0)
        #expect(names == [
            "client_id", "redirect_uri", "access_type", "response_type", "state",
            "matricola", "al_pj_matricola", "access_token", "scope",
            "al_id_srv", "al_id_srv_chiamante",
        ])
    }

    /// The failure this is about: a token minted without the scopes reaches
    /// the right endpoint and is refused with 401.
    @Test("Un login chiede tutti gli scope, codificati")
    func loginAsksForTheScopes() {
        let url = PoliMiOAuth.authorizationURL(params: params)
        #expect(value("scope", in: url) == "agenda+carriera+webeep")
    }

    @Test("Il redirect_uri viaggia codificato, non grezzo")
    func redirectIsEscaped() {
        let url = PoliMiOAuth.authorizationURL(params: params)
        #expect(value("redirect_uri", in: url) == "https%3A%2F%2Fpolimiapp.polimi.it%2Fpolimi_app%2Fapp")
    }

    @Test("Lo stato chiesto è quello che parte")
    func stateTravels() {
        let url = PoliMiOAuth.authorizationURL(params: params, state: "abc-123")
        #expect(value("state", in: url) == "abc-123")
    }

    /// A login has nothing to prove yet, and no enrolment to bind to unless
    /// one is hinted.
    @Test("Un login parte senza matricola e senza token")
    func loginCarriesNoIdentity() {
        let url = PoliMiOAuth.authorizationURL(params: params)
        #expect(value("matricola", in: url) == "")
        #expect(value("al_pj_matricola", in: url) == "")
        #expect(value("access_token", in: url) == "")
    }

    /// The hint goes in both keys, as the official app sends it.
    @Test("La matricola suggerita finisce in tutt’e due le chiavi")
    func loginWithAHint() {
        let url = PoliMiOAuth.authorizationURL(params: params, flow: .login(hintMatricola: "986617"))
        #expect(value("matricola", in: url) == "986617")
        #expect(value("al_pj_matricola", in: url) == "986617")
        #expect(value("access_token", in: url) == "", "Un login non ha ancora un token da esibire")
        #expect(value("scope", in: url) == "agenda+carriera+webeep",
                "Un login con suggerimento resta un login, e deve chiedere gli scope")
    }

    // MARK: Cambio carriera

    @Test("Un cambio carriera va al suo endpoint")
    func careerChangeEndpoint() {
        let url = PoliMiOAuth.authorizationURL(
            params: params, flow: .careerChange(matricola: "337940", accessToken: "tok"))
        #expect(url.absoluteString.hasPrefix("https://oauthidp.polimi.it/oauthidp/oauth2/careerChange?"))
    }

    /// It moves an existing grant rather than asking for a new one, so it
    /// sends no scope and does show the token that proves who is asking.
    @Test("Un cambio carriera non chiede scope ed esibisce il token")
    func careerChangeParameters() {
        let url = PoliMiOAuth.authorizationURL(
            params: params, flow: .careerChange(matricola: "337940", accessToken: "tok-123"))
        #expect(value("scope", in: url) == "")
        #expect(value("access_token", in: url) == "tok-123")
        #expect(value("matricola", in: url) == "337940")
        #expect(value("al_pj_matricola", in: url) == "337940")
    }

    @Test("La matricola del flusso è quella del flusso")
    func flowMatricola() {
        #expect(PoliMiOAuth.AuthorizationFlow.login().matricola == nil)
        #expect(PoliMiOAuth.AuthorizationFlow.login(hintMatricola: "986617").matricola == "986617")
        #expect(PoliMiOAuth.AuthorizationFlow.careerChange(matricola: "337940", accessToken: "t")
            .matricola == "337940")
    }

    // MARK: Il codice che torna

    /// Parsed rather than cut out of the string: the IdP appends `state` and
    /// reorders parameters, and a string replacement breaks the moment it does.
    @Test("Il codice si legge dalla query, in qualunque ordine")
    func authCode() {
        let withState = URL(string: "\(PoliMiOAuth.redirectURI)?state=abc&code=XYZ789")!
        let codeFirst = URL(string: "\(PoliMiOAuth.redirectURI)?code=XYZ789&state=abc")!
        #expect(PoliMiOAuth.authCode(from: withState) == "XYZ789")
        #expect(PoliMiOAuth.authCode(from: codeFirst) == "XYZ789")
    }

    @Test("Un indirizzo che non è il nostro redirect non dà codice")
    func authCodeFromAnotherURL() {
        #expect(PoliMiOAuth.authCode(from: URL(string: "https://example.com/app?code=XYZ")!) == nil)
    }

    /// The IdP redirects back on failure too, with an error instead of a code.
    @Test("Un redirect senza codice non inventa un codice")
    func authCodeMissing() {
        #expect(PoliMiOAuth.authCode(from: URL(string: "\(PoliMiOAuth.redirectURI)?error=access_denied")!) == nil)
        #expect(PoliMiOAuth.authCode(from: URL(string: PoliMiOAuth.redirectURI)!) == nil)
    }

    // MARK: Le chiamate

    /// The exchange and the refresh happen before there is a token to send
    /// with them; marking them authenticated would send the old one, or none.
    @Test("Lo scambio del codice non è autenticato e porta il codice nel percorso")
    func tokenExchange() {
        let request = PoliMiOAuth.tokenExchangeRequest(authCode: "XYZ789")
        #expect(request.path == "/jaf/oauth/token/get/XYZ789")
        #expect(!request.authenticated)
    }

    @Test("Il rinnovo porta il refresh token nel percorso")
    func refresh() {
        let request = PoliMiOAuth.refreshRequest(refreshToken: "ref-123")
        #expect(request.path == "/jaf/oauth/token/refresh/ref-123")
        #expect(!request.authenticated)
    }

    @Test("Il link di logout chiede la lingua e il servizio")
    func logoutLink() {
        let request = PoliMiOAuth.logoutLinkRequest(serviceID: "2428")
        #expect(request.path == "/jaf/public/linklogout")
        #expect(request.query.first { $0.name == "logout_service_id" }?.value == "2428")
        #expect(request.query.contains { $0.name == "lang" })
        #expect(!request.authenticated)
    }

    @Test("La revoca è una POST")
    func revoke() {
        #expect(PoliMiOAuth.revokeRequest.method == "POST")
        #expect(PoliMiOAuth.revokeRequest.path == "/jaf/oauth/revoke")
    }
}
