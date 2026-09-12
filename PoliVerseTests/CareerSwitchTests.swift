import Foundation
import Testing
@testable import PoliVerse

/// Switching career is an OAuth flow, not a parameter.
///
/// One person has one `codicePersona` and a matricola per enrolment — a
/// finished triennale and a starting magistrale, say. The token is bound to
/// **one** of them, which is why `iae` answers "Utente non abilitato Code: 6"
/// for the other: the career is closed, so its services are.
///
/// The official app switches by re-authorising against `/careerChange`,
/// verified from its bundle:
///
/// ```js
/// const m = `${oauthServer}/${n ? "careerChange" : "auth"}`
/// new URLSearchParams({..., matricola: n, al_pj_matricola: n,
///                      access_token: a, scope: n ? "" : t.scope})
/// ```
@Suite("Career switch")
struct CareerSwitchTests {
    private func query(_ url: URL) -> [String: String] {
        var found: [String: String] = [:]
        for pair in (url.query ?? "").split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            let key = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            found[key] = value.removingPercentEncoding ?? value
        }
        return found
    }

    @Test("An ordinary login still authorises against /auth")
    func plainLogin() {
        let url = PoliMiOAuth.authorizationURL(state: "abc")
        #expect(url.path.hasSuffix("/auth"))
        #expect(query(url)["matricola"] == "")
        #expect(query(url)["access_token"] == "")
        #expect(query(url)["scope"]?.isEmpty == false)
    }

    @Test("A career change authorises against /careerChange")
    func careerChangeEndpoint() {
        let url = PoliMiOAuth.authorizationURL(
            state: "abc", flow: .careerChange(matricola: "986617", accessToken: "tok"))
        #expect(url.path.hasSuffix("/careerChange"))
    }

    /// The route actually used, now that /careerChange errors server-side:
    /// a full login that asks to land on a particular enrolment. It must stay
    /// on /auth and keep the full scope, or the new token has no authority.
    @Test("A hinted login stays a login: /auth, full scope, no token")
    func hintedLogin() {
        let url = PoliMiOAuth.authorizationURL(
            state: "abc", flow: .login(hintMatricola: "332218"))
        #expect(url.path.hasSuffix("/auth"))
        let found = query(url)
        #expect(found["matricola"] == "332218")
        #expect(found["al_pj_matricola"] == "332218")
        #expect(found["access_token"] == "")
        #expect(found["scope"]?.isEmpty == false)
    }

    @Test("The chosen matricola is sent under both names the IdP reads")
    func matricolaSentTwice() {
        let found = query(PoliMiOAuth.authorizationURL(
            state: "abc", flow: .careerChange(matricola: "986617", accessToken: "tok")))
        #expect(found["matricola"] == "986617")
        #expect(found["al_pj_matricola"] == "986617")
    }

    /// The current token is the evidence of who is asking; without it the IdP
    /// has no session to move.
    @Test("The current access token is carried")
    func carriesToken() {
        let found = query(PoliMiOAuth.authorizationURL(
            state: "abc", flow: .careerChange(matricola: "986617", accessToken: "tok-123")))
        #expect(found["access_token"] == "tok-123")
    }

    /// `scope: n ? "" : t.scope` — a career change asks for no scopes, since
    /// it is moving an existing grant rather than requesting a new one.
    /// Sending the full list here is the difference between a switch and a
    /// fresh consent prompt.
    @Test("A career change requests no scopes")
    func emptyScope() {
        let found = query(PoliMiOAuth.authorizationURL(
            state: "abc", flow: .careerChange(matricola: "986617", accessToken: "tok")))
        #expect(found["scope"] == "")
    }

    @Test("The state is preserved so the response can be matched")
    func state() {
        let found = query(PoliMiOAuth.authorizationURL(
            state: "xyz-1", flow: .careerChange(matricola: "986617", accessToken: "tok")))
        #expect(found["state"] == "xyz-1")
    }
}

/// `GET /v1/careers/list`, the switcher's own endpoint.
///
/// Field names are VERIFIED from the bundle, which renders each row as
/// `L.matricola`, `L.desc_tipo_carriera?.[lang]` and
/// `L.desc_stato_carriera?.[lang]`.
@Suite("Careers list")
struct CareersListTests {
    private func careers(_ json: String) -> [Career] {
        (try? JSONDecoder().decode(CareersResponse.self, from: Data(json.utf8)))?.careers ?? []
    }

    private let real = """
    [{"matricola":"986617",
      "desc_tipo_carriera":{"it":"Laurea Triennale","en":"Bachelor"},
      "desc_stato_carriera":{"it":"Chiusa","en":"Closed"}},
     {"matricola":"332218",
      "desc_tipo_carriera":{"it":"Laurea Magistrale","en":"Master"},
      "desc_stato_carriera":{"it":"Attiva","en":"Active"}}]
    """

    @Test("Both careers decode with their kind and status")
    func decodes() {
        let parsed = careers(real)
        #expect(parsed.count == 2)
        #expect(parsed[0].matricola == "986617")
        #expect(parsed[0].kind == "Laurea Triennale")
        #expect(parsed[0].status == "Chiusa")
        #expect(parsed[1].kind == "Laurea Magistrale")
    }

    /// The status decides which career the app should default to, and getting
    /// it wrong is exactly the bug being fixed: pointing at the closed career
    /// makes every exam service answer "Utente non abilitato".
    @Test("An active career is recognised, a closed one is not")
    func activeDetection() {
        let parsed = careers(real)
        #expect(!parsed[0].isActive)
        #expect(parsed[1].isActive)
    }

    @Test("English status is understood too")
    func englishStatus() {
        let parsed = careers("""
        [{"matricola":"1","desc_stato_carriera":{"en":"Active"}}]
        """)
        #expect(parsed[0].isActive)
    }

    @Test("The active career is preferred when choosing a default")
    func defaultChoice() {
        #expect(Career.preferred(in: careers(real))?.matricola == "332218")
    }

    /// With nothing marked active, the app must still choose something rather
    /// than leaving every request unparameterised.
    @Test("With no active career the first is used")
    func noActiveCareer() {
        let parsed = careers("""
        [{"matricola":"111","desc_stato_carriera":{"it":"Chiusa"}},
         {"matricola":"222","desc_stato_carriera":{"it":"Chiusa"}}]
        """)
        #expect(Career.preferred(in: parsed)?.matricola == "111")
    }

    @Test("A row without a matricola is dropped")
    func missingMatricola() {
        #expect(careers("""
        [{"desc_tipo_carriera":{"it":"x"}}]
        """).isEmpty)
    }

    @Test("A wrapped array is found")
    func wrapped() {
        #expect(careers("""
        {"carriere":[{"matricola":"9"}]}
        """).count == 1)
    }
}
