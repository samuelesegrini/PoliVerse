import Foundation
import Testing
@testable import PoliVerse

/// Which authorization is being asked for, and what goes with it.
///
/// A login and a career change differ in four parameters at once — endpoint,
/// matricola, access token and scope — and getting one wrong silently produces
/// the other flow. None of it shows up as a bad request: it shows up as a
/// feature that does not work, or as a token that comes back with no authority.
///
/// The encoding of those values, and reading the code out of the redirect, are
/// pinned in `ServiceDirectoryTests` and `ModelTests`; this is the flow.
@Suite("Flussi OAuth")
struct PoliMiOAuthFlowTests {
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
