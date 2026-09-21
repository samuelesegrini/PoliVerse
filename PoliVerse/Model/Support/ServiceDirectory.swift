import Foundation
import Observation
import OSLog

/// Where each Politecnico service currently lives.
///
/// ## Why this is fetched rather than hardcoded
///
/// The official web app does not hardcode service hosts. On boot it fetches
/// `/polimi_app/rest/jaf/public/props` — unauthenticated — and reads the base
/// URL of every backend out of it:
///
/// ```json
/// {
///   "iae.base_url":      "https://api.polimi.it/iae",
///   "libretto.base_url": "https://api.polimi.it/piano_studente",
///   "ws_aule.base_url":  "https://api.polimi.it/ws_aule",
///   "maps.base_url":     "https://onlineservices.polimi.it/maps_rest/rest"
/// }
/// ```
///
/// That indirection is exactly why the official app survived the move off
/// `www22.dmz.polimi.it` and PoliFemo did not: PoliFemo baked the old host into
/// a constant in 2023 and still ships it. Reading the same config means a
/// future migration costs us nothing.
///
/// The agenda is the exception — its base is a build-time constant in the
/// official bundle (`REACT_APP_AGENDA_REST_PATH`), not part of `props`.
@Observable
final class ServiceDirectory {
    /// Backends the app talks to.
    nonisolated enum Service: String, CaseIterable, Sendable {
        /// The JAF layer: login, token exchange, user identity.
        case app
        /// Courses, exam sittings, enrolment.
        case iae
        /// Timetable.
        case agenda
        /// Study plan and grade simulation.
        case libretto
        /// WeBeep's Moodle.
        case weBeep
        /// The room catalogue with its bookings — what is busy and when.
        case wsAule
        /// The campus map service: which rooms exist, in which building, on
        /// which floor. Public and needing no token, unlike ``wsAule``, which
        /// answers what is *happening* in them.
        ///
        /// Listed here rather than hardcoded because four models were each
        /// carrying their own copy of the URL, which is precisely the drift
        /// this directory exists to prevent.
        case maps

        /// Key in the `props` payload, where one exists.
        var propsKey: String? {
            switch self {
            case .iae: "iae.base_url"
            case .libretto: "libretto.base_url"
            case .wsAule: "ws_aule.base_url"
            case .app, .agenda, .weBeep, .maps: nil
            }
        }

        /// Key holding this service's own profile value in `props`.
        ///
        /// Distinct from the signed-in user's profile. The official app builds
        /// its client for these hosts as
        /// `Qr({baseURL, profile: Number(props["iae.profile"])})`, and `Qr`
        /// presets `poliAuthProfile` from that — so calls to `iae` and
        /// `libretto` carry the *service* profile (`0`), not the user's.
        var profileKey: String? {
            switch self {
            case .iae: "iae.profile"
            case .libretto: "libretto.profile"
            case .wsAule: "ws_aule.profile"
            case .app, .agenda, .weBeep, .maps: nil
            }
        }

        /// Whether a 401 from this service means the session is broken.
        ///
        /// For most services it does: if `iae` refuses the token, the token
        /// is the problem and the user needs to sign in again. `ws_aule` is
        /// the exception — it is refused to student accounts by design, and
        /// letting that refusal set the session-wide "authorisation failed"
        /// flag put a re-login banner across an app in which everything else
        /// was working perfectly.
        var refusalMeansBrokenSession: Bool {
            switch self {
            // Unauthenticated, so a refusal from it says nothing about the
            // session either.
            case .wsAule, .maps: false
            case .app, .iae, .agenda, .libretto, .weBeep: true
            }
        }

        /// Service profile used until `props` loads. `nil` means "use the
        /// signed-in user's profile".
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

        /// Used until `props` is loaded, and if the fetch fails.
        /// Current as of 2026-09-11.
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

    /// OAuth client configuration, served by the Politecnico itself.
    ///
    /// The official app fetches this rather than hardcoding — and it matters:
    /// the scope list changes. As of 2026-09-11 it grants `agenda`, `so2`,
    /// `prenotazioni`, `presence_hub`, `cataloghi_aule` and others that did not
    /// exist in 2023, and no longer lists `esami` or `incarichidocente`.
    ///
    /// A token minted without `agenda` is rejected by the agenda service with
    /// 401 — the endpoint is right, the token simply has no authority over it.
    /// That is exactly the failure a hardcoded scope list produces, and it is
    /// indistinguishable from a broken login until you compare the lists.
    nonisolated struct OAuthParams: Decodable, Sendable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case oauthServer, clientId, scope, responseType, accessType
        }

        let oauthServer: String
        let clientId: String
        let scope: String
        let responseType: String?
        let accessType: String?

        /// PolimiApp's service id, used for the **logout** link.
        ///
        /// `/jaf/public/app?al_id_srv=2428` answers
        /// `descSrvCorrente: {"it": "PoliMI APP"}`, and the official bundle
        /// passes the same value as `logout_service_id`.
        ///
        /// - Note: it is *not* used on authorize. The IdP drops `al_id_srv`
        ///   there — probing with it empty and with `2428` returns a
        ///   byte-identical redirect, signature included.
        var serviceID: String = "2428"

        /// Baked-in copy of the live values, used until the fetch lands.
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

        var authorizationEndpoint: URL? { URL(string: oauthServer + "/auth") }
        /// Where the IdP moves an existing grant to another enrolment.
        var careerChangeEndpoint: URL? { URL(string: oauthServer + "/careerChange") }
    }

    private(set) var resolved: [Service: URL] = [:]
    /// Per-service `poliAuthProfile` values read from `props`.
    private(set) var serviceProfiles: [Service: Int] = [:]
    /// The signed-in account's secondary profile, if it has one.
    var dProfile: String?
    private(set) var oauth: OAuthParams = .fallback
    private(set) var didLoad = false

    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "directory")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func baseURL(for service: Service) -> URL {
        resolved[service] ?? service.fallback
    }

    /// The `poliAuthProfile` to send for a service.
    ///
    /// A service that declares its own profile in `props` wins; otherwise the
    /// signed-in user's profile is used, which is what the official app's
    /// interceptor falls back to.
    func profile(for service: Service, userProfile: Int) -> Int {
        serviceProfiles[service] ?? service.fallbackProfile ?? userProfile
    }

    /// Fetches the service map and OAuth config. Both are unauthenticated, so
    /// this runs before login — which it must, since the OAuth config is what
    /// the login is built from.
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
