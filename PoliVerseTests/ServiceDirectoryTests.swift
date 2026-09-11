import Testing
import Foundation
@testable import PoliVerse

/// The official web app resolves every backend through
/// `/polimi_app/rest/jaf/public/props` instead of hardcoding hosts. That is why
/// it survived `www22.dmz.polimi.it/iae` becoming `api.polimi.it/iae` and
/// PoliFemo — which baked the old host into a constant in 2023 — did not.
@Suite("Service directory")
@MainActor
struct ServiceDirectoryTests {
    @Test("Before loading, every service falls back to a usable base")
    func fallbacksUsableImmediately() {
        let directory = ServiceDirectory()
        for service in ServiceDirectory.Service.allCases {
            let url = directory.baseURL(for: service)
            #expect(url.scheme == "https", "\(service.rawValue) must be https")
            #expect(url.host?.isEmpty == false)
        }
    }

    /// The fallbacks are what ship in the binary, so a regression here means
    /// shipping a build that talks to a host that no longer answers.
    @Test("Fallbacks point at the hosts verified live on 2026-09-11")
    func fallbacksMatchVerifiedHosts() {
        let directory = ServiceDirectory()
        #expect(directory.baseURL(for: .iae).absoluteString
                == "https://api.polimi.it/iae")
        #expect(directory.baseURL(for: .agenda).absoluteString
                == "https://api.polimi.it/agenda")
        #expect(directory.baseURL(for: .libretto).absoluteString
                == "https://api.polimi.it/piano_studente")
        #expect(directory.baseURL(for: .app).absoluteString
                == "https://polimiapp.polimi.it/polimi_app/rest")

        // The host PoliFemo still ships. If this ever becomes a fallback again,
        // something has gone badly wrong.
        for service in ServiceDirectory.Service.allCases {
            #expect(directory.baseURL(for: service).host != "www22.dmz.polimi.it")
        }
    }

    @Test("Only services that appear in props carry a key")
    func propsKeysAreCorrect() {
        #expect(ServiceDirectory.Service.iae.propsKey == "iae.base_url")
        #expect(ServiceDirectory.Service.libretto.propsKey == "libretto.base_url")
        // The agenda base is a build-time constant in the official bundle
        // (REACT_APP_AGENDA_REST_PATH), not part of props.
        #expect(ServiceDirectory.Service.agenda.propsKey == nil)
        #expect(ServiceDirectory.Service.app.propsKey == nil)
        #expect(ServiceDirectory.Service.weBeep.propsKey == nil)
    }

    /// `props` is a flat string map; decoding it as anything richer would break
    /// on the empty values it contains (`"piani.base_url": ""`).
    @Test("A props payload shaped like the real one decodes")
    func decodesRealisticProps() throws {
        let payload = """
        {"maps.base_url":"https://onlineservices.polimi.it/maps_rest/rest",\
        "piani.base_url":"","piani.profile":"","libretto.profile":"0",\
        "libretto.base_url":"https://api.polimi.it/piano_studente",\
        "iae.profile":"0","iae.base_url":"https://api.polimi.it/iae"}
        """
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))

        #expect(decoded["iae.base_url"] == "https://api.polimi.it/iae")
        #expect(decoded["libretto.base_url"] == "https://api.polimi.it/piano_studente")
        // Empty values must be ignored rather than becoming a base URL of "".
        #expect(decoded["piani.base_url"] == "")
    }
}

@Suite("OAuth scope drift")
struct OAuthScopeTests {
    /// The live scope list as of 2026-09-11. A token minted without `agenda`
    /// reaches the agenda service and is refused with 401 — the endpoint is
    /// correct, the token simply has no authority over it.
    @Test("The fallback scope includes what the services actually need")
    func fallbackScopeCoversServices() {
        let scope = ServiceDirectory.OAuthParams.fallback.scope
        for required in ["agenda", "carriera", "webeep", "polimi_app", "pianostudente", "react_iae"] {
            #expect(scope.contains(required), "scope must grant \(required)")
        }
    }

    /// These were in PoliFemo's 2023 list and are gone from the live one.
    @Test("Scopes the IdP no longer publishes are not requested")
    func staleScopesDropped() {
        let scope = ServiceDirectory.OAuthParams.fallback.scope
        #expect(scope.contains("incarichidocente") == false)
        // "esami" is gone as a standalone scope; guard against a bare match.
        #expect(scope.split(separator: " ").contains("esami") == false)
    }

    @Test("The authorization URL carries the fetched scope, not a baked-in one")
    func authorizationURLUsesParams() throws {
        let custom = ServiceDirectory.OAuthParams(
            oauthServer: "https://example.com/oauth2",
            clientId: "999",
            scope: "openid something_new",
            responseType: "code",
            accessType: "offline"
        )
        let components = try #require(URLComponents(
            url: PoliMiOAuth.authorizationURL(params: custom), resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }

        #expect(components.host == "example.com")
        #expect(value("client_id") == "999")
        #expect(value("scope") == "openid something_new")
    }

    /// The official app builds this with `URLSearchParams`, so every key is
    /// present even when empty. Matching it exactly removes a whole class of
    /// "maybe it is the missing parameter" guesswork.
    ///
    /// `al_id_srv` is deliberately empty: probing the IdP with it empty and
    /// with `2428` returns a byte-identical redirect, signature included, so
    /// the parameter is dropped and a non-empty value fixes nothing.
    @Test("The authorize request mirrors the official one")
    func authorizationMirrorsOfficial() throws {
        let components = try #require(URLComponents(
            url: PoliMiOAuth.authorizationURL(), resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }

        for key in ["client_id", "redirect_uri", "access_type", "response_type",
                    "state", "matricola", "al_pj_matricola", "access_token",
                    "scope", "al_id_srv", "al_id_srv_chiamante"] {
            #expect(items.contains { $0.name == key }, "authorize must send \(key)")
        }

        #expect(value("al_id_srv") == "")
        #expect(value("matricola") == "")
        #expect(value("access_token") == "")
        #expect(value("state")?.isEmpty == false)
        // No trailing slash, no path, no query — the official value exactly.
        #expect(value("redirect_uri") == "https://polimiapp.polimi.it/polimi_app/app")
    }

    /// The logout link ends the SSO session, which is what actually forces a
    /// new grant; without it the IdP can replay the old one.
    @Test("The logout link request is public and names the service")
    func logoutLinkRequest() {
        let request = PoliMiOAuth.logoutLinkRequest()
        #expect(request.authenticated == false)
        #expect(request.path == "/jaf/public/linklogout")
        #expect(request.query.contains { $0.name == "logout_service_id" && $0.value == "2428" })
    }

    /// An expired token and a wrongly-scoped one are both 401 and need opposite
    /// responses — refresh versus re-login — so they must be told apart.
    @Test("The wrong-scope 401 is distinguished from an expired token")
    func detectsInvalidScope() {
        let scopeError = #"{"statusCode":401,"message":"jaf.model2.exceptions.JafUnauthorizedException: Scope OAuth non valido. Effettuare logout/login o disinstallare e reinstallare l'applicazione. Code: 33"}"#
        #expect(PoliMiAPI.isInvalidScope(scopeError))

        #expect(PoliMiAPI.isInvalidScope(
            #"{"statusCode":401,"message":"(POLIJ_033001) Il servizio richiede autenticazione"}"#) == false)
        #expect(PoliMiAPI.isInvalidScope("") == false)
    }

    /// The whole point of recording the scope: spotting a token that predates
    /// a change so the app can re-authenticate instead of 401-ing forever.
    @Test("A token remembers the scope it was granted")
    func tokenRecordsScope() throws {
        var token = PoliMiToken(accessToken: "a", refreshToken: "b", expiresIn: 3600)
        token.grantedScope = "openid agenda"

        let data = try JSONEncoder().encode(PoliMiToken.Stored(token))
        let restored = try JSONDecoder().decode(PoliMiToken.Stored.self, from: data).token

        #expect(restored.grantedScope == "openid agenda")
        #expect(restored.accessToken == "a")
    }
}
