import Foundation
import Observation
import OSLog

/// Where each Politecnico backend currently lives, and the OAuth client
/// configuration to sign in with.
///
/// Both are fetched rather than hardcoded, from two unauthenticated endpoints on
/// the `polimiapp` host: `/jaf/public/props` for the service map and the
/// per-service profile values, and `/jaf/oauth/params` for the OAuth client.
/// ``load()`` performs both, and every value has a baked-in fallback used until it
/// lands and after a failure.
///
/// The indirection matters in two places. Service hosts move, and a build that
/// reads `props` follows them. The OAuth scope list also changes, and a token
/// minted without a scope is refused by that one service with 401 while the login
/// itself succeeds — a failure indistinguishable from a broken sign-in unless the
/// granted scope is compared against the current one, which ``TokenStore`` does.
@Observable
final class ServiceDirectory {
    /// The backends the app talks to.
    nonisolated enum Service: String, CaseIterable, Sendable {
        /// The JAF layer: sign-in, token exchange and user identity.
        case app
        /// Courses, exam sittings and enrolment.
        case iae
        /// The timetable. Its base URL is a build-time constant in the official client
        /// rather than part of `props`, so it has no ``propsKey``.
        case agenda
        /// The study plan and grade simulation.
        case libretto
        /// WeBeep's Moodle instance.
        case weBeep
        /// The room catalogue with its bookings — what is busy and when. Refused to
        /// student accounts by design; see ``refusalMeansBrokenSession``.
        case wsAule
        /// The campus map service: which rooms exist, in which building and on which
        /// floor.
        ///
        /// Public and needing no token, unlike ``wsAule``, which answers what is happening
        /// in them.
        case maps

        /// This service's base-URL key in the `props` payload, or `nil` when `props` does
        /// not carry one and ``fallback`` is always used.
        var propsKey: String? {
            switch self {
            case .iae: "iae.base_url"
            case .libretto: "libretto.base_url"
            case .wsAule: "ws_aule.base_url"
            case .app, .agenda, .weBeep, .maps: nil
            }
        }

        /// This service's own profile key in the `props` payload, or `nil` when it has
        /// none.
        ///
        /// Distinct from the signed-in student's profile: the official client presets
        /// `poliAuthProfile` on these hosts from the service's value rather than the
        /// user's.
        var profileKey: String? {
            switch self {
            case .iae: "iae.profile"
            case .libretto: "libretto.profile"
            case .wsAule: "ws_aule.profile"
            case .app, .agenda, .weBeep, .maps: nil
            }
        }

        /// Whether a 401 from this service means the session itself is broken.
        ///
        /// `false` for ``wsAule`` and ``maps``, which are refused to student accounts or
        /// need no token at all. Letting either set the session-wide authorisation flag
        /// would put a re-login banner over an app in which everything else works.
        var refusalMeansBrokenSession: Bool {
            switch self {
            // Unauthenticated, so a refusal from it says nothing about the
            // session either.
            case .wsAule, .maps: false
            case .app, .iae, .agenda, .libretto, .weBeep: true
            }
        }

        /// The service profile to send until `props` loads, or `nil` to send the signed-in
        /// student's.
        ///
        /// ``wsAule`` is `3` rather than `0`, and the difference is load-bearing: a
        /// non-zero service profile is the condition under which the official client
        /// appends a `matricola` parameter.
        var fallbackProfile: Int? {
            switch self {
            case .iae, .libretto: 0
            // Not zero, unlike the others — and the difference is load
            // bearing: a non-zero service profile is exactly the condition
            // under which the official client appends `matricola`.
            case .wsAule: 3
            case .app, .agenda, .weBeep, .maps: nil
            }
        }

        /// The base URL to use until `props` loads, and if the fetch fails. Current as of
        /// 2026-09-11.
        var fallback: URL {
            switch self {
            case .app: URL(string: "https://polimiapp.polimi.it/polimi_app/rest")!
            case .iae: URL(string: "https://api.polimi.it/iae")!
            case .agenda: URL(string: "https://api.polimi.it/agenda")!
            case .libretto: URL(string: "https://api.polimi.it/piano_studente")!
            case .weBeep: URL(string: "https://webeep.polimi.it")!
            case .wsAule: URL(string: "https://api.polimi.it/ws_aule")!
            case .maps: URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!
            }
        }
    }

    /// The OAuth client configuration, served by the Politecnico at
    /// `/jaf/oauth/params`.
    nonisolated struct OAuthParams: Decodable, Sendable, Equatable {
        /// Only the five fields the endpoint sends. ``serviceID`` is the app's own.
        private enum CodingKeys: String, CodingKey {
            case oauthServer, clientId, scope, responseType, accessType
        }

        /// Base URL of the identity provider's OAuth 2 endpoints.
        let oauthServer: String
        /// The OAuth client identifier to authorise as.
        let clientId: String
        /// The space-separated scopes to request.
        ///
        /// Recorded on the minted token as ``PoliMiToken/grantedScope``, since refreshing
        /// never widens a token's scopes.
        let scope: String
        /// The OAuth response type, `code` in practice.
        let responseType: String?
        /// The OAuth access type, `offline` in practice, which yields a refresh token.
        let accessType: String?

        /// PolimiApp's service id, sent as `logout_service_id` on the sign-out link.
        ///
        /// - Note: Not used when authorising. The identity provider ignores `al_id_srv`
        ///   there.
        var serviceID: String = "2428"

        /// A baked-in copy of the live configuration, used until the fetch lands and after
        /// a failure. Current as of 2026-09-11.
        static let fallback = OAuthParams(
            oauthServer: "https://oauthidp.polimi.it/oauthidp/oauth2",
            clientId: "1057407812",
            scope: """
            aule policard portale_so incarichi orario account webmail \
            compila_quest openid rubrica richass guasti prenotazione code \
            carriera alumni webeep richieste_occupazione maps polimi_app \
            teamwork faqappmobile rich_sing_occup react_iae \
            multichance_richieste_ausili pianostudente incattdid \
            presentazionepianireact cataloghi_aule agenda so2 prenotazioni \
            presence_hub
            """.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            responseType: "code",
            accessType: "offline",
            serviceID: "2428"
        )

        /// Where a sign-in begins, or `nil` when ``oauthServer`` is not a valid URL.
        var authorizationEndpoint: URL? { URL(string: oauthServer + "/auth") }
        /// Where the identity provider moves an existing grant to another enrolment, or
        /// `nil` when ``oauthServer`` is not a valid URL.
        var careerChangeEndpoint: URL? { URL(string: oauthServer + "/careerChange") }
    }

    /// Base URLs read from `props`. A service absent here uses its ``Service/fallback``.
    private(set) var resolved: [Service: URL] = [:]
    /// Per-service `poliAuthProfile` values read from `props`.
    private(set) var serviceProfiles: [Service: Int] = [:]
    /// The signed-in account's secondary profile, sent as `poliAuthD_profile`. `nil`
    /// for a plain student account.
    var dProfile: String?
    /// The OAuth client configuration in force.
    private(set) var oauth: OAuthParams = .fallback
    /// Whether ``load()`` has run. Set even when the fetch fails, so the fallbacks are
    /// not re-attempted on every call.
    private(set) var didLoad = false

    /// Diagnostic log for this type, under the `directory` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "directory")
    /// The session the two configuration fetches are issued through.
    private let session: URLSession

    /// Creates a directory holding only the fallbacks. Call ``load()`` to resolve them.
    ///
    /// - Parameter session: The session the configuration fetches are issued through.
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The base URL for a service.
    ///
    /// - Parameter service: The backend to address.
    /// - Returns: The resolved URL, or ``Service/fallback`` when `props` has not
    ///   supplied one.
    func baseURL(for service: Service) -> URL {
        resolved[service] ?? service.fallback
    }

    /// The `poliAuthProfile` to send for a service.
    ///
    /// A service's own value from `props` wins, then its ``Service/fallbackProfile``,
    /// then the signed-in student's.
    ///
    /// - Parameters:
    ///   - service: The backend being addressed.
    ///   - userProfile: The signed-in student's profile. See ``PoliMiProfile``.
    /// - Returns: The profile value to send.
    func profile(for service: Service, userProfile: Int) -> Int {
        serviceProfiles[service] ?? service.fallbackProfile ?? userProfile
    }

    /// Fetches the OAuth configuration and the service map.
    ///
    /// Both endpoints are unauthenticated, so this runs before sign-in — which it must,
    /// since the sign-in is built from the OAuth configuration. Returns immediately
    /// once ``didLoad`` is set.
    ///
    /// A failure, a non-success status or an undecodable payload leaves the fallbacks
    /// in place and still marks the directory loaded. A resolved URL that differs from
    /// its fallback is logged, since it means the baked-in value is stale.
    func load() async {
        guard !didLoad else { return }
        await loadOAuthParams()

        let url = Service.app.fallback.appendingPathComponent("/jaf/public/props")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log.error("props returned a non-success status; keeping fallbacks")
                didLoad = true
                return
            }

            let props = try await BackgroundJSON.decode([String: String].self, from: data)
            var profiles: [Service: Int] = [:]
            for service in Service.allCases {
                if let key = service.profileKey,
                   let raw = props[key], let value = Int(raw) {
                    profiles[service] = value
                }
            }
            serviceProfiles = profiles

            var map: [Service: URL] = [:]
            for service in Service.allCases {
                guard
                    let key = service.propsKey,
                    let value = props[key],
                    !value.isEmpty,
                    let resolvedURL = URL(string: value)
                else { continue }

                map[service] = resolvedURL
                if resolvedURL != service.fallback {
                    // Worth shouting about: it means a service moved and the
                    // fallback baked into this build is now stale.
                    log.notice("\(service.rawValue, privacy: .public) moved to \(value, privacy: .public)")
                }
            }
            resolved = map
            didLoad = true
            log.info("Service directory loaded (\(map.count) entries)")
        } catch {
            log.error("props fetch failed: \(error.localizedDescription); keeping fallbacks")
            didLoad = true
        }
    }

    /// Fetches `/jaf/oauth/params` into ``oauth``, keeping ``OAuthParams/fallback`` on
    /// any failure.
    ///
    /// A scope list that differs from the one in force is logged, because a scope
    /// change is what silently breaks a client with a hardcoded list.
    private func loadOAuthParams() async {
        let url = Service.app.fallback.appendingPathComponent("/jaf/oauth/params")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log.error("oauth params returned a non-success status; keeping fallback")
                return
            }

            let params = try await BackgroundJSON.decode(OAuthParams.self, from: data)
            if params.scope != oauth.scope {
                // Loud, because a scope change is what silently breaks a
                // hardcoded client: the login still succeeds and individual
                // services start answering 401.
                log.notice("OAuth scopes changed upstream")
            }
            oauth = params
            log.info("OAuth params loaded (client \(params.clientId, privacy: .public))")
        } catch {
            log.error("oauth params fetch failed: \(error.localizedDescription); keeping fallback")
        }
    }
}
